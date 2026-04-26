# Envoy AI Gateway v0.4 to v0.5 Migration Plan

이 문서는 Envoy AI Gateway v0.4 basic baseline을 v0.5 환경으로 옮기기 위한 migration 계획과 검증 결과를 정리한다.

현재 basic scenario는 **검증 완료** 상태다. v0.4 source manifest가 v0.5 CRD/controller 환경에서 수정 없이 적용되고, 동일 curl 요청이 HTTP 200 OK를 반환했다.

## 핵심 방향

단순히 v0.5 example을 새로 설치하는 것은 migration이 아니다. 이 프로젝트에서 migration은 다음 과정을 의미한다.

1. **검증 완료**: v0.4 basic baseline을 기준점으로 확보한다.
2. **검증 완료**: v0.5 클러스터와 controller를 별도로 구성한다.
3. **검증 완료**: v0.4 basic manifest를 v0.5 환경에 먼저 적용해 실패 지점을 확인한다.
4. **검증 완료**: v0.5 tag의 example과 공식 문서를 참고해 v0.4 manifest를 v0.5 schema와 비교한다.
5. **검증 완료**: 수정 전/후 diff를 문서화한다. basic scenario는 no-op migration이다.
6. **검증 완료**: v0.4와 같은 curl scenario가 v0.5에서도 HTTP 200으로 동작하는지 확인한다.

## 목표

- v0.4 baseline manifest가 v0.5에서 깨지는지 확인한다.
- v0.5에 맞춘 migrated manifest를 `manifests/v05/`에 고정한다.
- 변경 전/후 차이를 문서화해 migration guide로 남긴다. basic scenario는 파일 차이가 없다.
- Memory PoC에서 활용할 v0.5 기능의 실제 사용 지점을 확인한다.
  - GatewayConfig
  - `schema.version`에서 `schema.prefix`로의 전환
  - Body Mutation
  - Header Mutation
  - ExtProc 설정 방식

## 현재까지 확인한 v0.5 tag 정보

**검증 완료**

로컬 WSL에서 `envoyproxy/ai-gateway`의 `v0.5.0` tag를 clone해 확인했다.

```text
v0.5.0 tag commit: b40501fe
```

Helm chart도 OCI registry에서 조회 가능했다.

```text
ai-gateway-helm appVersion: v0.5.0
ai-gateway-helm chart version: v0.5.0
ai-gateway-crds-helm appVersion: v0.5.0
ai-gateway-crds-helm chart version: v0.5.0
```

**검증 완료**

`examples/basic/basic.yaml`은 v0.4.0과 v0.5.0 tag에서 동일한 파일이다.

```text
v0.4 basic sha256: 051cc1b5b4f31ec0dd0f4e01005f0ef469dba77acae4460fa86dcf73c0f81182
v0.5 basic sha256: 051cc1b5b4f31ec0dd0f4e01005f0ef469dba77acae4460fa86dcf73c0f81182
```

따라서 basic manifest 자체는 v0.4에서 v0.5로 넘어갈 때 diff가 없을 수 있다. 다만 이것이 migration 검증이 끝났다는 뜻은 아니다. v0.5 CRD/controller 위에서 실제 apply와 route/backend reconciliation을 확인해야 한다.

**검토 필요**

v0.5 tag의 `site/docs/compatibility.md`에는 `main`과 `v0.4.x` 행만 있고, `v0.5.x` 행이 명시되어 있지 않았다. chart는 v0.5.0이 존재하므로 실제 설치 검증을 기준으로 판단한다.

**검증 완료**

v0.5 CRD 기준 `AIServiceBackend.spec.schema`에는 `prefix` 필드가 있고, `version`은 OpenAI prefix 호환 용도의 deprecated behavior로 설명되어 있다.

**검증 완료**

v0.5 CRD 기준 Body Mutation과 Header Mutation 필드는 `AIServiceBackend`와 `AIGatewayRoute` backend reference 쪽에 존재한다. Body Mutation은 top-level field set/remove와 최대 16개 제한이 CRD description에 명시되어 있다.

**검증 완료**

v0.5 CRD 기준 `GatewayConfig`는 `aigateway.envoyproxy.io/v1alpha1`이며, Gateway annotation `aigateway.envoyproxy.io/gateway-config`로 참조한다. 실제 CRD schema는 `spec.extProc.kubernetes.env`와 `spec.extProc.kubernetes.resources` 구조를 가진다.

## 작업 단위

### Step 1. v0.4 manifest 고정

**검증 완료**

v0.4 baseline에서 검증한 manifest를 `manifests/v04/`에 복사한다.

대상:

```text
~/workspace/ai-gateway-v04/examples/basic/basic.yaml
```

보관 위치:

```text
manifests/v04/basic.yaml
```

목적:

- migration source를 명확히 고정한다.
- 이후 v0.5 migrated manifest와 diff를 비교할 수 있게 한다.

예상 결과:

- `manifests/v04/basic.yaml`이 v0.4 기준 원본으로 남는다.
- main 브랜치 raw URL을 사용하지 않는다.

현재 보관됨:

```text
manifests/v04/basic.yaml
```

### Step 2. v0.5 환경 구성

**검증 완료**

v0.4와 섞이지 않도록 별도 Kind cluster를 사용한다.

```bash
kind create cluster --name aigw-v05 --image kindest/node:v1.32.0
kubectl config use-context kind-aigw-v05
```

검증한 버전:

- Kubernetes: v1.32.0
- Envoy Gateway: v1.6.0
- Envoy AI Gateway CRD chart: v0.5.0
- Envoy AI Gateway controller chart: v0.5.0

namespace 기본 전략:

- Envoy Gateway: `envoy-gateway-system`
- Envoy AI Gateway: `envoy-ai-gateway-system`
- migrated basic resources: `default`

### Step 3. v0.4 manifest를 v0.5 환경에 그대로 적용

**검증 완료**

v0.5 CRD와 controller가 설치된 상태에서 v0.4 basic manifest를 그대로 적용한다.

```bash
kubectl apply -f manifests/v04/basic.yaml
```

목적:

- 실제 migration failure를 확인한다.
- 어떤 kind, apiVersion, field, status 조건이 깨지는지 기록한다.

실패를 기록할 항목:

- `kubectl apply` 에러 메시지
- CRD kind mismatch
- field validation error
- deprecated field warning
- controller reconciliation error
- Gateway / route / backend status 조건

기록 위치:

```text
logs/v05-migration-result.md
docs/02-v05-migration-plan.md
docs/99-troubleshooting.md
```

실제 결과:

- `kubectl apply` 에러 없음
- `AIGatewayRoute` Accepted
- `AIServiceBackend` Accepted
- curl HTTP 200 OK

### Step 4. v0.5 tag example과 비교

**검증 완료**

v0.5 example은 migration target을 이해하기 위한 참고 자료로 사용한다. v0.5 example 자체를 그대로 설치하는 것이 목표는 아니다.

```bash
git clone --branch v0.5.0 https://github.com/envoyproxy/ai-gateway.git ~/workspace/ai-gateway-v05
cd ~/workspace/ai-gateway-v05
find examples -maxdepth 2 -type f | sort
grep -R "schema:" -n examples manifests | head -50
grep -R "GatewayConfig\\|bodyMutation\\|headerMutation\\|externalProcessor\\|schema.version\\|schema.prefix" -n examples manifests | head -100
```

확인할 변경점:

- v0.4 basic example과 v0.5 basic example의 kind 차이
- `AIGatewayRoute` spec 차이
- `AIServiceBackend` spec 차이
- `BackendSecurityPolicy` 또는 credential 관련 차이
- `schema.version` 사용 여부
- `schema.prefix` 사용 여부
- `GatewayConfig` 사용 여부
- Body Mutation / Header Mutation 예제 위치

현재 보관됨:

```text
manifests/v05/basic-upstream.yaml
```

확인 결과:

- v0.4.0 `examples/basic/basic.yaml`과 v0.5.0 `examples/basic/basic.yaml`은 동일하다.
- 따라서 basic scenario의 manifest 변경은 없을 수 있다.
- 실제 migration 검증은 v0.5 controller/CRD 위에서 v0.4 manifest가 그대로 Accepted 되는지 확인해야 한다.

### Step 5. v0.5 migrated manifest 작성

**검증 완료**

v0.4 source manifest를 v0.5 schema에 맞게 수정해 `manifests/v05/basic-migrated.yaml`로 저장한다.

보관 위치:

```text
manifests/v05/basic-migrated.yaml
```

작성 원칙:

- v0.4와 동일한 client-facing behavior를 유지한다.
- 기존 curl 요청 path와 header를 가능한 유지한다.
- 꼭 필요한 변경만 반영한다.
- 변경 이유를 문서에 남긴다.

basic scenario 결과:

- v0.4 source manifest와 v0.5 upstream basic manifest가 동일하다.
- 따라서 `manifests/v05/basic-migrated.yaml`은 `manifests/v04/basic.yaml`과 동일하다.
- 이 migration은 basic scenario 기준 no-op migration으로 기록한다.

비교 명령:

```bash
git diff -- manifests/v04/basic.yaml manifests/v05/basic-migrated.yaml
```

### Step 6. v0.5 migrated manifest 적용 및 검증

**검증 완료**

```bash
kubectl apply -f manifests/v05/basic-migrated.yaml
```

상태 확인:

```bash
kubectl get gateway
kubectl describe gateway envoy-ai-gateway-basic
kubectl get aigatewayroute
kubectl describe aigatewayroute envoy-ai-gateway-basic
kubectl get aiservicebackend
kubectl describe aiservicebackend envoy-ai-gateway-basic-testupstream
kubectl get pods -n envoy-gateway-system
```

port-forward:

```bash
export ENVOY_SERVICE=$(kubectl get svc -n envoy-gateway-system \
  --selector=gateway.envoyproxy.io/owning-gateway-namespace=default,gateway.envoyproxy.io/owning-gateway-name=envoy-ai-gateway-basic \
  -o jsonpath='{.items[0].metadata.name}')

kubectl port-forward -n envoy-gateway-system svc/$ENVOY_SERVICE 8080:80
```

curl:

```bash
curl -i \
  -H "Content-Type: application/json" \
  -H "x-ai-eg-model: some-cool-self-hosted-model" \
  -d '{
    "model": "some-cool-self-hosted-model",
    "messages": [
      {
        "role": "system",
        "content": "Hi."
      }
    ]
  }' \
  http://localhost:8080/v1/chat/completions
```

성공 기준:

- Kubernetes node가 `Ready` 상태다.
- Envoy Gateway Pod가 `Running` 상태다.
- Envoy AI Gateway Controller Pod가 `Running` 상태다.
- migrated manifest가 v0.5 CRD 기준으로 적용된다.
- route/backend 리소스가 Accepted 상태다.
- `/v1/chat/completions` 요청이 HTTP `200 OK`를 반환한다.
- v0.4와 v0.5의 manifest 차이가 문서화되어 있다.

검증 결과:

- `aigw-v05` node Ready
- Envoy Gateway Pod Running
- AI Gateway Controller Pod Running
- Envoy data plane Pod Running
- `AIGatewayRoute` Accepted
- `AIServiceBackend` Accepted
- `/v1/chat/completions` HTTP 200 OK

상세 결과:

```text
logs/v05-migration-result.md
```

## 확인해야 할 v0.5 변경점

### GatewayConfig

**검증 완료**

검증한 항목:

- `GatewayConfig` CRD의 실제 apiVersion과 kind
- Gateway와 GatewayConfig 연결 방식
- ExtProc container resource 설정 위치
- ExtProc 환경변수 설정 가능 여부
- Redis URL, TTL, max history length 같은 Memory 설정을 둘 수 있는지

검증 결과:

- `GatewayConfig` apiVersion은 `aigateway.envoyproxy.io/v1alpha1`이다.
- Gateway annotation `aigateway.envoyproxy.io/gateway-config=memory-poc-gateway-config`로 GatewayConfig를 연결한다.
- `spec.extProc.kubernetes.env`에 둔 `MEMORY_POC_MARKER`, `MEMORY_TTL_SECONDS`, `MEMORY_MAX_HISTORY_MESSAGES`, `REDIS_URL` 값이 `ai-gateway-extproc` 컨테이너 env로 반영된다.
- `spec.extProc.kubernetes.resources`에 둔 requests/limits가 `ai-gateway-extproc` 컨테이너 resources로 반영된다.
- 단, 이미 떠 있는 data plane Pod에는 즉시 반영되지 않았다. 로컬 검증에서는 data plane Deployment rollout restart 후 새 Pod에서 반영을 확인했다.

검증 manifest:

```text
manifests/v05/gateway-config.yaml
```

검증 스크립트:

```bash
./scripts/verify-gateway-config-v05.sh
```

상세 결과:

```text
logs/v05-gateway-config-result.md
```

### `schema.version`에서 `schema.prefix`로 전환

**검증 완료**

킥오프 문서 기준으로 `schema.version`은 deprecated이고 `schema.prefix` 사용이 필요하다.

확인 결과:

- v0.5 CRD에서 `AIServiceBackend.spec.schema.prefix` 필드를 확인했다.
- OpenAI schema에서 `prefix: /v1`을 명시하면 backend endpoint는 `/v1/chat/completions`로 계산된다.
- `manifests/v05/schema-prefix-backend.yaml`을 적용한 뒤 `AIServiceBackend`는 `Accepted` 상태를 유지했다.
- 기존 client 요청 path `/v1/chat/completions`는 변경하지 않아도 HTTP 200 OK를 반환했다.

검증 스크립트:

```bash
./scripts/verify-schema-prefix-v05.sh
```

상세 결과:

```text
logs/v05-schema-prefix-result.md
```

### Body Mutation

**부분 검증 완료 / 추가 검토 필요**

Memory PoC에서는 요청 body의 `messages`를 history가 포함된 배열로 바꾸는 기능이 필요하다.

확인 결과:

- CRD 설명 기준 Body Mutation은 top-level field만 지원한다.
- `AIServiceBackend.spec.bodyMutation.set`으로 request body의 top-level `model` field 변경을 확인했다.
- `AIGatewayRoute.spec.rules.backendRefs[].bodyMutation`는 리소스상 `Accepted` 되었지만, 이번 관측 기준에서는 backend 응답의 `x-model` 변경이 확인되지 않았다. 추가 확인이 필요하다.
- `messages` 배열 전체 교체 가능성은 아직 **검토 필요**다.
- response body mutation 지원 여부는 아직 **검토 필요**다.

상세 결과:

```text
logs/v05-body-mutation-result.md
```

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

## 스크립트

**검증 완료**

추가 및 검증한 스크립트:

```text
scripts/setup-v05.sh
scripts/verify-v05.sh
scripts/cleanup-v05.sh
```

역할:

- `setup-v05.sh`: v0.5 클러스터와 controller 설치, v0.4 manifest 적용 시도, migrated manifest 적용
- `verify-v05.sh`: route/backend/Gateway 상태와 curl 검증 안내
- `cleanup-v05.sh`: `aigw-v05` cluster 삭제. 삭제 전 사용자 확인 필수

주의:

- destructive 작업은 자동화하지 않는다.
- v0.4 manifest가 v0.5에서 실패하면 정상적인 migration evidence로 기록한다.
- main 브랜치 raw URL은 사용하지 않는다.

## 현재 미검증 항목

다음 항목은 모두 **검토 필요**다.

- Body Mutation으로 `messages` 배열 전체 교체가 가능한지
- Header Mutation의 실제 제한과 동작 방식
- ExtProc로 request/response body를 모두 처리하는 설정
- Memory PoC에 필요한 response 저장 흐름
