# 02 · 장애 시나리오 (주입과 복구)

L7과 L4 장애를 동시에 주입해 "원인이 여럿이고 계층도 다른" 상황을 만든다.
장애 주입은 설정 변경일 뿐 트래픽이 아니므로 데이터는 쌓이지 않는다. 데이터는 요청이 흐를 때만 발생한다.

## 사전 설정 — reviews를 v2로 고정

reviews v2/v3만 ratings를 호출하므로, ratings 경로가 항상 살아있도록 v2로 고정한다.

```yaml
# routing-pin-v2.yaml  (namespace: bookinfo)
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: { name: reviews, namespace: bookinfo }
spec:
  host: reviews
  subsets:
    - { name: v1, labels: { version: v1 } }
    - { name: v2, labels: { version: v2 } }
    - { name: v3, labels: { version: v3 } }
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: { name: reviews, namespace: bookinfo }
spec:
  hosts: [reviews]
  http:
    - route:
        - destination: { host: reviews, subset: v2 }
```

## L7 장애 — ratings에 HTTP 500 주입 (앱 계층)

TCP 연결은 성공하고 애플리케이션이 500을 응답한다. Envoy response_flags는 FI(Fault Injected).

```yaml
# fault-l7-ratings.yaml  (namespace: bookinfo)
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: { name: ratings, namespace: bookinfo }
spec:
  hosts: [ratings]
  http:
    - fault:
        abort:
          percentage: { value: 100 }
          httpStatus: 500
      route:
        - destination: { host: ratings }
```

```bash
kubectl apply -f fault-l7-ratings.yaml
```

사용자 화면: productpage 별점 영역에 "Ratings service is currently unavailable".

## L4 장애 — details 파드 0개 (전송 계층)

엔드포인트가 없어 TCP 연결 자체가 실패한다. Envoy response_flags는 UH(No Healthy Upstream), 로그에는 connection refused.

```bash
kubectl scale deploy details -n bookinfo --replicas=0
```

사용자 화면: productpage 상세 영역에 "Error fetching product details".

## 두 장애의 신호 비교

| 도구 | L7 (ratings 500) | L4 (details 0) |
|---|---|---|
| Kiali 그래프 | reviews→ratings 엣지 빨강 | productpage→details 엣지 빨강 |
| Metric (Mimir) | response_code=500, response_flags=FI | response_code=503, response_flags=UH |
| Log (Loki) | fault_filter_abort | no healthy upstream / connection refused |
| 구성 (kubectl) | ratings VS에 fault 블록 | details replicas=0 |

response_flags로 계층을 구분한다. FI는 애플리케이션 계층(L7)에서 주입된 에러, UH/UF/UC는 연결 실패(L4)를 뜻한다.

## 트래픽 생성 (on-demand)

```bash
kubectl -n bookinfo port-forward svc/productpage 9080:9080 &
for i in $(seq 1 200); do curl -s -o /dev/null http://localhost:9080/productpage; sleep 0.2; done
```

부하 루프는 데모/리허설 때만 실행하고 종료(Ctrl+C)한다. 방치하지 않으면 누적은 수 MB 수준이다.

## 복구

```bash
kubectl scale deploy details -n bookinfo --replicas=1
kubectl delete vs ratings -n bookinfo
```

Kiali 그래프가 정상으로 돌아오고 productpage가 복구된다.

## 옵션

- 동시 주입은 임팩트가 크고, 순차 주입은 설명이 쉽다. 발표 스타일에 맞춰 선택한다.
- L7을 abort(500) 대신 delay(지연)로 바꾸면 지연 장애도 연출할 수 있다.
- 발표에서 복구까지 보여줄지, 진단에서 마칠지는 선택한다.
