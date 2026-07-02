# 04 · AgentOps 진단 방법

수동 진단(문서 03)에서 사람이 도구 서너 개를 오가며 하던 상관분석을, awsops 대시보드가 한 번의 질문으로 대신한다.
내부적으로 incident 상관분석 엔진이 Mimir(메트릭), Loki(로그), K8s 이벤트, Istio 구성을 동시에 조회해 종합한다.

## 사전 조건

대시보드가 두 신호를 읽으려면 데이터소스가 등록되어 있어야 한다.

- awsops 대시보드 설정에 Mimir, Loki 데이터소스 등록
- 각 엔드포인트는 observability 네임스페이스의 서비스 주소 사용
- 등록 확인은 대시보드의 데이터소스 상태(health)로 점검

## 접근

```
https://kia-awsops.noticore.co.kr/awsops
```

로그인 후 AI 어시스턴트(또는 incident 분석 화면)로 이동한다.

## 질문

장애 주입 상태에서 다음과 같이 자연어로 묻는다.

```
productpage가 지금 장애야. Metric/Log를 종합해서 원인을 계층별로 찾아줘.
```

## 기대 응답

incident 엔진이 두 신호와 구성을 종합해 두 개의 독립 원인을 계층과 함께 제시한다.

- 원인 1 (L7): ratings에 VirtualService fault injection(HTTP 500 abort)이 설정됨. response_flags=FI. 조치: 해당 VirtualService의 fault 블록 제거.
- 원인 2 (L4): details 파드가 0개라 연결 실패(no healthy upstream, response_flags=UH). 조치: details를 replicas 1 이상으로 스케일.

한 번의 질문으로 두 신호가 통합되고, 계층 구분과 수정 방법까지 함께 나온다.

## 수동 방식과의 대비

| 항목 | 수동 (문서 03) | AgentOps |
|---|---|---|
| 도구 수 | Kiali + Grafana(Mimir/Loki) + kubectl | 대시보드 하나 |
| 질의 | PromQL, LogQL 직접 작성 | 자연어 한 문장 |
| 상관분석 | 사람이 타임스탬프 맞춰 추론 | 엔진이 자동 상관분석 |
| 계층 구분 | 사람이 response_flags 해석 | 결과에 포함 |
| 수정안 | 사람이 판단 | 결과에 포함 |

## 데모에서 짚을 점

- 수동 진단을 먼저 보여 "실무에서 이만큼 손이 간다"를 체감시킨 뒤 AgentOps를 보여주면 대비가 살아난다.
- 원인이 두 개이고 계층이 다르다는 점을 강조하면, 단순 조회가 아니라 상관분석의 가치가 드러난다.
- 검증 시 대시보드의 incident 엔진이 실제로 Mimir/Loki를 조회하는지(데이터소스 연결 상태) 사전에 확인해 둔다.
