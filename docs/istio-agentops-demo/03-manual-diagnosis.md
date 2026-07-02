# 03 · 수동 진단 방법

장애가 발생한 상태에서 사람이 직접 도구를 열어 원인을 찾는 절차다.
Metric, Log, Trace를 각각 다른 화면에서 보고 시간축을 맞춰 상관관계를 추론해야 한다.

## 도구 접근

```bash
export KUBECONFIG=~/.kube/config

# 앱
kubectl -n bookinfo port-forward svc/productpage 9080:9080
#   http://localhost:9080/productpage

# Kiali (메시 그래프)
kubectl -n istio-system port-forward svc/kiali 20001:20001
#   http://localhost:20001

# Grafana (Metric/Log/Trace 통합)
kubectl -n istio-system port-forward svc/grafana 3000:3000
#   http://localhost:3000
```

## 1단계. Kiali로 문제 위치 파악

Graph 화면에서 bookinfo 네임스페이스를 선택한다. 트래픽을 흘리면 엣지에 색이 입혀진다.

- productpage→details 엣지 빨강
- reviews→ratings 엣지 빨강

두 곳이 문제지만, Kiali만으로는 "왜" 깨졌는지(계층, 원인)까지는 알기 어렵다.

## 2단계. Grafana + Mimir로 메트릭 확인

Explore에서 데이터소스를 Mimir로 선택하고 다음 PromQL을 실행한다.

```promql
sum by (destination_service_name, response_code, response_flags)
  (rate(istio_requests_total{reporter="destination"}[1m]))
```

결과 해석:

- ratings: response_code=500, response_flags=FI  → 애플리케이션 계층(L7)
- details: response_code=503, response_flags=UH  → 연결 실패(L4)

지연도 함께 보려면:

```promql
histogram_quantile(0.95,
  sum by (destination_service_name, le)
    (rate(istio_request_duration_milliseconds_bucket[1m])))
```

## 3단계. Grafana + Loki로 로그 확인

데이터소스를 Loki로 전환하고 LogQL을 실행한다.

```logql
# L7: ratings 관련 500 / fault
{namespace="bookinfo"} |= "ratings" |~ "50[0-9]"

# L4: 연결 실패
{namespace="bookinfo"} |= "no healthy upstream"
{namespace="bookinfo"} |= "connection refused"
```

Envoy 액세스 로그에서 L7은 fault_filter_abort, L4는 upstream connect error / no healthy upstream이 보인다.

## 4단계. Grafana + Tempo로 트레이스 확인

데이터소스를 Tempo로 전환하고 TraceQL로 에러 트레이스를 찾는다.

```traceql
{ status = error }
{ resource.service.name = "ratings" && span.http.status_code = 500 }
{ resource.service.name = "details" }
```

트레이스를 열면 워터폴 뷰가 나온다.

- L7: productpage → reviews → ratings에서 ratings span이 빨강, http.status_code=500
- L4: productpage → details 구간이 HTTP 응답 전에 끊김(connection error span)

## 5단계. Istio 구성으로 근본 원인 확인

```bash
# L7 근본 원인: fault injection
kubectl get vs ratings -n bookinfo -o yaml
#   http.fault.abort.httpStatus: 500

# L4 근본 원인: 엔드포인트 없음
kubectl get deploy details -n bookinfo          # READY 0/0
kubectl get endpoints details -n bookinfo        # 엔드포인트 비어 있음
```

## 상관관계 정리

다섯 개 화면(Kiali, Grafana Mimir/Loki/Tempo, kubectl)의 결과를 시간축으로 맞춰 종합하면 다음 결론에 도달한다.

- 원인 1(L7): ratings VirtualService에 HTTP 500 fault injection이 설정됨
- 원인 2(L4): details 파드가 0개라 연결 실패

## 이 방식의 한계

도구 네다섯 개를 오가며 PromQL, LogQL, TraceQL을 손으로 작성하고, 각 화면의 타임스탬프를 맞춰가며 사람이 직접 상관관계를 추론해야 한다. 원인이 여러 개이고 계층이 다르면 시간이 더 걸린다. 이 지점이 AgentOps와의 대비 포인트다(문서 04).
