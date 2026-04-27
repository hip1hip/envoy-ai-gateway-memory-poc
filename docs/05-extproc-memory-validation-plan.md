# ExtProc Memory 검증 계획

## 상태

**계획 / 검토 필요**

이 문서는 v0.5 migration 후 Memory PoC로 넘어가기 위한 ExtProc 검증 계획이다. 아직 custom Memory ExtProc 구현은 시작하지 않았다.

## 목적

session-based short-term memory를 플랫폼 레벨에서 제공하려면 request/response 흐름 중 다음 처리가 필요하다.

- request header에서 `x-session-id` 읽기
- request body의 `messages` 읽기
- Redis에서 session history 조회
- request body의 `messages`에 history 병합
- response body에서 assistant message 추출
- Redis에 user/assistant message 저장

Body Mutation 검증 결과 top-level field 변경은 가능했지만, Redis 조회와 `messages[*]` 병합에는 한계가 있다. 따라서 다음 핵심 검증은 ExtProc 기반으로 진행한다.

## 현재까지 확인한 근거

**검증 완료**

- `GatewayConfig`는 Gateway annotation으로 연결된다.
- `GatewayConfig.spec.extProc.kubernetes.env/resources`는 `ai-gateway-extproc` 컨테이너에 반영된다.
- v0.5 CRD 기준 `GatewayConfig.spec.extProc.kubernetes.image`, `imageRepository`, `volumeMounts`, `securityContext` 필드가 존재한다.
- Helm 기본값 기준 extProc 기본 이미지는 `docker.io/envoyproxy/ai-gateway-extproc`이다.

## 핵심 질문

다음 항목은 모두 **검토 필요**다.

- Envoy AI Gateway가 생성하는 data plane의 extProc 컨테이너를 custom image로 교체할 수 있는가?
- custom image가 기존 `ai-gateway-extproc`와 동일한 gRPC External Processor contract를 구현해야 하는가?
- request body 전체를 custom ExtProc에서 읽을 수 있는가?
- request body를 수정해서 backend로 전달할 수 있는가?
- response body를 custom ExtProc에서 읽고 Redis에 저장할 수 있는가?
- streaming response에서 body 저장을 어디까지 지원할 수 있는가?

## 검증 단계

### Step 1. ExtProc image 교체 가능성 확인

**검증 완료**

목적:

- `GatewayConfig.spec.extProc.kubernetes.image` 또는 `imageRepository`로 data plane의 `ai-gateway-extproc` image가 교체되는지 확인한다.

예상 산출물:

```text
manifests/v05/extproc-image-override.yaml
scripts/verify-extproc-image-v05.sh
logs/v05-extproc-image-result.md
```

성공 기준:

- GatewayConfig가 `Accepted` 상태다.
- data plane rollout 후 `ai-gateway-extproc` 컨테이너 image가 지정한 값으로 바뀐다.
- 잘못된 image를 넣었을 때 Pod가 `ImagePullBackOff`가 되는지 확인해 image override가 실제 적용됐음을 증명한다.

검증 결과:

- `GatewayConfig.spec.extProc.kubernetes.image`로 `ai-gateway-extproc` sidecar image가 바뀌는 것을 확인했다.
- invalid image 적용 후 새 Pod는 `ErrImagePull` 상태가 됐다.
- 원래 GatewayConfig로 복구 후 data plane Pod가 다시 `3/3 Running` 상태가 됐다.
- 상세 결과는 `logs/v05-extproc-image-result.md`에 기록했다.

주의:

- 이 단계에서는 정상 custom ExtProc를 구현하지 않는다.
- 실패 image를 쓰는 경우 data plane이 깨질 수 있으므로 별도 cluster 또는 즉시 원복 절차가 필요하다.

### Step 2. 최소 custom ExtProc skeleton 구현

**검증 완료**

목적:

- 기존 `ai-gateway-extproc`를 대체할 수 있는 최소 gRPC server를 만든다.
- 우선 request/response를 변경하지 않고 pass-through 동작만 확인한다.

예상 산출물:

```text
extproc-memory/
  pyproject.toml
  src/extproc_memory/
  tests/
docker/
  extproc-memory.Dockerfile
```

성공 기준:

- image build 성공
- Kind cluster에 image load 성공
- GatewayConfig로 custom image 적용
- `/v1/chat/completions` HTTP 200 유지

검증 결과:

- v0.5 upstream `ai-gateway-extproc` 소스를 기반으로 custom image를 빌드했다.
- build 시 `internal/version.version=v0.5.0-0-gb40501fe` ldflags를 넣어 config version mismatch를 해결했다.
- Kind cluster에 image를 load했다.
- `GatewayConfig.spec.extProc.kubernetes.image`로 custom image를 적용했다.
- `/v1/chat/completions` 요청이 HTTP 200 OK를 반환했다.

### Step 3. request header/body inspect

**검증 완료**

목적:

- custom ExtProc가 `x-session-id`와 request body를 읽을 수 있는지 확인한다.

성공 기준:

- custom ExtProc log에 `x-session-id`가 기록된다.
- request body의 `model`, `messages` 개수를 기록한다.

검증 결과:

- custom ExtProc log에서 request body의 `messages` 개수를 읽어 `original_messages=1`로 기록했다.
- Header Mutation 검증 설정이 남아 있어 backend에는 `X-Session-Id: header-mutated-session`이 전달됐다.

### Step 4. request body mutation

**검증 완료**

목적:

- custom ExtProc가 request body의 `messages` 배열을 수정해 backend로 전달할 수 있는지 확인한다.

성공 기준:

- backend log 또는 응답 헤더로 mutation 결과를 확인한다.
- 기존 Body Mutation보다 세밀한 `messages` 병합 가능성을 확인한다.

검증 결과:

- Redis 없이 dummy system message를 `messages` 앞에 주입했다.
- custom ExtProc log에서 `mutated_messages=2`를 확인했다.
- test upstream log에서 request body length가 기존 147 bytes에서 213 bytes로 증가했다.
- HTTP 200 OK가 유지됐다.

상세 결과:

```text
logs/v05-memory-extproc-skeleton-result.md
```

### Step 5. Redis 연동

**계획**

목적:

- `x-session-id` 기준으로 Redis에 최근 N개 message를 저장한다.

성공 기준:

- 첫 요청 후 Redis key가 생성된다.
- 두 번째 요청에서 같은 session history가 조회된다.
- TTL과 sliding window가 동작한다.

## 권장 다음 액션

다음 작업은 Step 1인 **ExtProc image override 검증**으로 제한한다.

이유:

- custom ExtProc 구현 전에 GatewayConfig로 컨테이너 image 교체가 실제 가능한지 먼저 확인해야 한다.
- image override가 안 되면 Memory 구현 방식은 ExtProc 대체가 아니라 별도 Memory Service 또는 다른 Envoy extension 경로로 바뀐다.
