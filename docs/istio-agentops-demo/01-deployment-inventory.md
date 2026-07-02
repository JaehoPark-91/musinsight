# 01 · 배포 인벤토리 & 아키텍처

이 데모를 위해 EKS(`awsops-eks`)에 배포하는 구성요소 전체 목록과 역할, 연결 관계.

## 1. 신규 배포 컴포넌트

### A. 서비스 메시 (`istio-system`)
| 컴포넌트 | 역할 | 파드 |
|---|---|---|
| **istiod** | 메시 컨트롤플레인 (사이드카 주입, 정책, 인증서 발급) | 1 |
| **istio-ingressgateway** | 메시 진입 게이트웨이 | 1 |
| **mTLS PeerAuthentication (STRICT)** | 서비스 간 통신 전부 암호화 강제 | (설정) |

### B. 데모 앱 (`bookinfo`, istio-injection=enabled)
| 서비스 | 역할 | 파드 |
|---|---|---|
| **productpage** | 프론트, details·reviews 호출 | 1 |
| **details** | 상품 상세 | 1 |
| **reviews** (v1/v2/v3) | 리뷰. v2/v3는 ratings 호출 | 3 |
| **ratings** | 별점 | 1 |

> 각 파드에 **istio-proxy(Envoy) 사이드카**가 자동 주입됨 → 메트릭·로그의 원천.
> 데모 결정성 위해 **reviews를 v2로 100% 고정**(ratings 항상 호출).

### C. 관측 백엔드 (`observability`, 전부 모놀리식·emptyDir)
| 신호 | 도구 | 역할 | 파드 |
|---|---|---|---|
| Metric | **Mimir** | 메트릭 저장·조회 (PromQL 호환) | 1 |
| Log | **Loki** | 로그 저장·조회 (LogQL) | 1 |

### D. 수집기 (`observability`)
| 컴포넌트 | 역할 | 파드 |
|---|---|---|
| **Grafana Alloy** | Envoy 메트릭→Mimir, 로그→Loki (2종 통합 수집) | ~3 (DaemonSet) |

### E. 수동 진단 UI (`istio-system`)
| 도구 | 용도 | 파드 |
|---|---|---|
| **Kiali** | 메시 서비스 그래프 (엣지별 에러율·mTLS) | 1 |
| **Grafana** | Metric/Log 통합 뷰어 (Mimir·Loki 데이터소스) | 1 |

**신규 합계 ≈ 15 파드** → 기존 16 + 15 = **~31 / 51** (워커 3대, 여유 있음)

## 2. 기존 구성 (안 건드림)
| 컴포넌트 | 위치 | 역할 |
|---|---|---|
| Prometheus + OpenCost | `opencost` | 컨테이너 **비용** (메시 라인과 완전 별개) |
| awsops 대시보드 + AgentCore | EC2 / Bedrock | **AgentOps** (incident 상관분석 엔진) |

## 3. 데이터 흐름

```
[생산]          [수집]        [저장·조회]       [소비 / UI]
Istio/Envoy ─metric→ Alloy ──→ Mimir ──┐─→ Grafana (수동)  ← 사람이 탭 넘기며
            ─log───→ Alloy ──→ Loki  ──┘─→ awsops 대시보드 (AgentOps) ← 한 질문
Istio 구성(VS/DR/mTLS) ─────────────────→ Kiali (그래프) + awsops(Steampipe SQL)

노드/파드 메트릭 → Prometheus(opencost) → OpenCost → awsops (비용, 별개)
```

## 4. 각 도구 접근법 (port-forward)

```bash
export KUBECONFIG=~/.kube/config

# 앱 (productpage)
kubectl -n bookinfo port-forward svc/productpage 9080:9080
#   → http://localhost:9080/productpage

# Kiali (메시 그래프)
kubectl -n istio-system port-forward svc/kiali 20001:20001
#   → http://localhost:20001

# Grafana (Metric/Log 통합)
kubectl -n istio-system port-forward svc/grafana 3000:3000
#   → http://localhost:3000  (Explore에서 datasource 전환)
```

## 5. 설정/배선 체크 (파드 외 필수)
- Istio Telemetry: **액세스로그 ON**
- Grafana 데이터소스: Mimir / Loki 등록
- **awsops 대시보드 데이터소스: Mimir / Loki 등록** ← AgentOps incident 엔진이 읽음
- OpenCost Prometheus는 그대로 (비용 전용)

## 6. 리소스/용량 메모
- 저장 = **emptyDir**(임시). 파드 재시작 시 데이터 소멸 (데모엔 무방).
- 데이터 = **트래픽량에 비례**. 트래픽 on-demand → 유휴 누적 ≈ 0.
- Loki retention 6h (보험).
- 워커 노드 파드 한도 17/노드 → 총 51. 현재 ~32 사용.
