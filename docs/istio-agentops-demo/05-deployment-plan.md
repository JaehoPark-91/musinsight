# 05 · 배포 계획

Istio 메시와 관측 스택을 EKS(awsops-eks)에 올리는 순서와 명령이다.
저장은 emptyDir, Trace 샘플링 100%, 트래픽은 on-demand를 전제로 한다.

## 사전 준비

- kubectl, helm, istioctl (로컬 또는 EC2)
- KUBECONFIG가 awsops-eks를 가리키는지 확인: `kubectl get nodes` 에서 워커 3대 Ready
- 네임스페이스: istio-system, observability, bookinfo

## 1. Istio 설치와 mTLS

```bash
istioctl install --set profile=demo -y
kubectl label namespace bookinfo istio-injection=enabled --overwrite

# mTLS 전체 STRICT
kubectl apply -f - <<'EOF'
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata: { name: default, namespace: istio-system }
spec: { mtls: { mode: STRICT } }
EOF
```

## 2. Bookinfo 배포와 라우팅 고정

```bash
kubectl create namespace bookinfo
kubectl label namespace bookinfo istio-injection=enabled --overwrite
kubectl -n bookinfo apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/bookinfo/platform/kube/bookinfo.yaml
kubectl -n bookinfo apply -f routing-pin-v2.yaml   # 문서 02 참고
```

버전 태그는 설치한 istioctl 버전에 맞춘다.

## 3. 관측 백엔드 (Mimir, Loki, Tempo)

모두 모놀리식 모드, emptyDir, retention 6h로 설치한다. helm values로 지정한다.

```bash
kubectl create namespace observability
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Loki (single binary, filesystem, emptyDir)
helm install loki grafana/loki -n observability -f values-loki.yaml
# Tempo (monolithic)
helm install tempo grafana/tempo -n observability -f values-tempo.yaml
# Mimir (monolithic 또는 distributed 최소구성)
helm install mimir grafana/mimir-distributed -n observability -f values-mimir.yaml
```

values 파일에서 공통으로 지정할 것: persistence는 emptyDir 상당(비영속), 리소스 requests 소박하게, retention 6h.

## 4. Alloy (수집)

Alloy가 Envoy 메트릭을 스크레이프해 Mimir로 remote_write, 파드 로그를 Loki로, OTLP 트레이스를 Tempo로 전달한다.

```bash
helm install alloy grafana/alloy -n observability -f values-alloy.yaml
```

Alloy config 요지:

- prometheus.scrape: Envoy sidecar(/stats/prometheus, 15020) 대상 → remote_write → Mimir
- loki.source.kubernetes 또는 파일 → Loki
- otelcol.receiver.otlp → otelcol.exporter → Tempo

## 5. Istio 텔레메트리 설정

```bash
kubectl apply -f - <<'EOF'
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata: { name: mesh-default, namespace: istio-system }
spec:
  accessLogging:
    - providers: [{ name: envoy }]
  tracing:
    - providers: [{ name: otel }]
      randomSamplingPercentage: 100
EOF
```

트레이싱 provider(otel)는 istiod meshConfig의 extensionProviders에 Alloy(OTLP) 엔드포인트로 등록한다. 액세스 로그는 stdout으로 나가고 Alloy가 수집해 Loki로 보낸다.

## 6. Kiali와 Grafana

```bash
kubectl -n istio-system apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons/kiali.yaml
kubectl -n istio-system apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons/grafana.yaml
```

Kiali의 external_services.prometheus는 Mimir 쿼리 엔드포인트로 지정한다. Grafana에는 Mimir, Loki, Tempo 데이터소스를 등록한다.

## 7. awsops 대시보드 데이터소스 등록

대시보드 설정에서 Mimir, Loki, Tempo를 데이터소스로 등록한다. incident 상관분석 엔진이 이 세 개를 읽는다. 엔드포인트는 observability 네임스페이스 서비스 주소를 쓰되, EC2에서 접근 가능한 경로(예: 서비스 ClusterIP 대신 필요 시 port-forward나 내부 DNS)를 사용한다.

## 8. 검증

```bash
# 정상 트래픽
kubectl -n bookinfo port-forward svc/productpage 9080:9080 &
for i in $(seq 1 100); do curl -s -o /dev/null http://localhost:9080/productpage; done

# 각 도구에 데이터가 들어오는지 확인
# - Kiali 그래프에 트래픽 표시
# - Grafana Mimir: istio_requests_total 조회
# - Grafana Loki: bookinfo 로그 조회
# - Grafana Tempo: 트레이스 조회
# - awsops 대시보드: 데이터소스 health OK

# 장애 주입 → 수동 진단(03) → AgentOps 진단(04) 리허설
```

## 정리 순서 (데모 종료 후)

```bash
kubectl delete namespace bookinfo observability
istioctl uninstall --purge -y
kubectl delete namespace istio-system
```
