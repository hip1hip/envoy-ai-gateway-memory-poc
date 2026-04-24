# Envoy AI Gateway v0.5 Migration Plan

이 문서는 아직 직접 검증하지 않은 v0.5 migration 계획이다. 모든 항목은 **계획** 또는 **검토 필요** 상태로 취급한다.

## 목표

- v0.4 baseline을 기준점으로 삼아 v0.5 환경을 별도 구성한다.
- v0.5에서 변경된 CRD, Helm chart, manifest, 확장 기능을 확인한다.
- Memory PoC에서 활용할 수 있는 GatewayConfig, Body Mutation, Header Mutation, ExtProc 연계 지점을 검증한다.

## 작업 순서

1. **계획**: v0.5용 별도 Kind 클러스터 생성
   - 예: `aigw-v05`
   - Kubernetes 버전은 v0.5 공식 요구사항을 확인한 뒤 고정한다.

2. **검토 필요**: Envoy Gateway v1.6.x 설치
   - v0.5 문서에서 요구하는 Envoy Gateway 버전을 확인한다.
   - Helm chart 버전을 명시해서 설치한다.

3. **검토 필요**: Envoy AI Gateway v0.5.0 CRD와 Controller 설치
   - CRD chart와 controller chart 버전을 `v0.5.0`으로 고정한다.
   - namespace 전략을 v0.4와 동일하게 유지할지 확인한다.

4. **검토 필요**: v0.5 태그의 example 적용
   - main 브랜치 raw URL은 사용하지 않는다.
   - 반드시 `v0.5.0` 태그 기준 manifest를 사용한다.

5. **검토 필요**: v0.4 basic manifest와 v0.5 basic manifest 비교
   - CRD kind 변화
   - spec field 변화
   - route matching 방식 변화
   - backend 설정 변화
   - mutation 관련 설정 추가 여부

6. **검토 필요**: 기존 curl scenario 재검증
   - `x-ai-eg-model` 헤더 기반 route match가 동일하게 동작하는지 확인한다.
   - `/v1/chat/completions` 응답이 HTTP 200으로 돌아오는지 확인한다.

## 확인해야 할 변경점

### GatewayConfig

**검토 필요**

v0.5에서는 External Processor 관련 설정이 `GatewayConfig`로 이동하거나 확장되는 것으로 알려져 있다. 다음을 확인해야 한다.

- `GatewayConfig` CRD apiVersion과 kind
- Gateway와 GatewayConfig 연결 방식
- ExtProc container resource 설정 위치
- ExtProc 환경변수 설정 가능 여부
- Redis URL, TTL, max history length 같은 Memory 설정을 GatewayConfig에 둘 수 있는지

### `schema.version`에서 `schema.prefix`로 전환

**검토 필요**

킥오프 문서 기준으로 `schema.version`은 deprecated이고 `schema.prefix` 사용이 필요하다.

확인할 항목:

- v0.4 manifest에서 `schema.version` 사용 위치
- v0.5 manifest에서 `schema.prefix` 사용 위치
- 기존 path `/v1/chat/completions`와 prefix 설정의 관계
- 기존 client 요청 path 변경 필요 여부

### Body Mutation

**검토 필요**

Memory PoC에서는 요청 body의 `messages`를 history가 포함된 배열로 바꾸는 기능이 필요하다.

확인할 항목:

- Body Mutation이 top-level field만 지원하는지
- `messages` 배열 전체 교체가 가능한지
- 최대 mutation field 수 제한
- request body mutation과 response body mutation 지원 범위
- OpenAI compatible request body에 적용 가능한지

### Header Mutation

**검토 필요**

Header Mutation은 session id 전달, 내부 routing metadata, backend 전달 헤더 정리에 사용할 수 있다.

확인할 항목:

- `x-session-id`를 backend 또는 ExtProc로 전달할 수 있는지
- 내부용 헤더를 제거할 수 있는지
- route match에 쓰는 `x-ai-eg-model`과 충돌하지 않는지

### ExtProc / Memory 연계 지점

**검토 필요**

Memory 기능은 Gateway 자체에 내장된 기능이 아니므로 ExtProc 또는 외부 Memory Service 연계가 필요하다.

확인할 항목:

- v0.5에서 ExtProc 설정 방식
- request header/body를 ExtProc에서 읽고 수정할 수 있는지
- response body를 ExtProc에서 읽고 Redis에 저장할 수 있는지
- ExtProc 장애 시 요청 실패 정책
- Redis 장애 시 fail-fast 또는 fallback 정책

## v0.5 클러스터 / namespace / manifest 전략

**계획**

v0.4 baseline과 v0.5 migration을 섞지 않기 위해 별도 클러스터를 사용한다.

```bash
kind create cluster --name aigw-v05 --image kindest/node:<검토 필요>
kubectl config use-context kind-aigw-v05
```

namespace 초안:

- Envoy Gateway: `envoy-gateway-system`
- Envoy AI Gateway: `envoy-ai-gateway-system`
- PoC application resources: `default` 또는 `ai-gateway-poc`
- Redis: `ai-gateway-memory` 또는 `ai-gateway-poc`

manifest 디렉터리:

```text
manifests/
  v04/
  v05/
```

전략:

- `manifests/v04/`: v0.4 baseline에서 직접 수정하거나 고정한 manifest를 보관한다.
- `manifests/v05/`: v0.5 migration 중 검증한 manifest를 보관한다.
- remote raw URL은 main 브랜치를 사용하지 않고 버전 태그를 명시한다.

## v0.5 성공 기준 초안

**계획**

- Kubernetes node가 `Ready` 상태다.
- Envoy Gateway v1.6.x Pod가 `Running` 상태다.
- Envoy AI Gateway v0.5.0 Controller Pod가 `Running` 상태다.
- v0.5 basic example 리소스가 정상 적용된다.
- Gateway Listener가 `Accepted=True`, `ResolvedRefs=True`, `Programmed=True` 조건을 만족한다.
- v0.5 route/backend 리소스가 Accepted 상태다.
- port-forward 기반 `/v1/chat/completions` 요청에 HTTP 200을 받는다.
- Body Mutation 또는 Header Mutation이 최소 1개 이상 실제 동작한다.

## 아직 검증하지 않은 항목

다음 항목은 모두 **검토 필요**다.

- v0.5의 정확한 Kubernetes 최소 버전
- v0.5와 호환되는 Envoy Gateway chart 버전
- v0.5 example manifest의 실제 kind와 field
- `GatewayConfig`의 실제 schema
- Body Mutation의 실제 제한과 동작 방식
- Header Mutation의 실제 제한과 동작 방식
- ExtProc로 request/response body를 모두 처리하는 설정
- Memory PoC에 필요한 response 저장 흐름
