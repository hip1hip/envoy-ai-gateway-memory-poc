# v0.5 Memory ExtProc skeleton 검증 결과

## 상태

**검증 완료**

2026-04-27 기준 Kind `aigw-v05` 환경에서 Redis 없이 custom Memory ExtProc skeleton을 적용하고 request body inspect/mutation을 확인했다.

## 목적

Redis를 붙이기 전 다음 세 가지를 검증한다.

- custom ExtProc image가 기존 AI Gateway 흐름을 깨지 않는가
- request body의 `messages`를 읽을 수 있는가
- `messages` 앞에 dummy memory message를 주입할 수 있는가

## 구현 방식

완전히 새로운 ExtProc를 처음부터 작성하지 않았다.

대신 v0.5 upstream `ai-gateway-extproc` 소스를 복사한 뒤 작은 패치를 적용했다.

이유:

- 기본 `ai-gateway-extproc`는 routing, provider 변환, body/header mutation, metrics 처리를 이미 담당한다.
- 완전 신규 skeleton으로 대체하면 기존 AI Gateway 흐름이 깨질 수 있다.
- Memory PoC는 기존 흐름을 유지하면서 request/response 처리 지점만 확장하는 방향이 더 안전하다.

## 추가한 동작

환경변수:

```text
MEMORY_POC_DUMMY_INJECTION=true
```

동작:

- request body JSON을 읽는다.
- top-level `messages` 배열 길이를 확인한다.
- Redis 대신 dummy system message를 `messages` 앞에 추가한다.
- mutation 후 request를 backend로 보낸다.

dummy message:

```text
[memory-poc] dummy short-term memory injected before Redis integration.
```

## 빌드

실행:

```bash
./scripts/build-memory-extproc-v05.sh
```

결과:

```text
IMAGE_NAME=envoy-ai-gateway-memory-extproc:v0.5.0-memory-skeleton
```

중간 이슈:

- WSL에 `go`가 없어 Docker `golang:1.25` image 안에서 빌드하도록 수정했다.
- 처음 빌드한 binary는 version이 `dev`라서 config version `v0.5.0`과 mismatch가 발생했다.
- `-ldflags '-X github.com/envoyproxy/ai-gateway/internal/version.version=v0.5.0-0-gb40501fe'`를 추가해 해결했다.

## 검증

실행:

```bash
./scripts/verify-memory-extproc-skeleton-v05.sh
```

결과:

```text
POD=envoy-default-envoy-ai-gateway-basic-21a9f8f8-69496884cb-l8sjc
envoy-ai-gateway-memory-extproc:v0.5.0-memory-skeleton
HTTP_CODE=200
```

ExtProc log:

```text
memory poc injected dummy message original_messages=1 mutated_messages=2
```

test upstream log:

```text
Request body (213 bytes)
```

이전 Body Mutation 검증 설정이 남아 있어 test upstream의 model은 `body-mutated-model`로 감지됐다. Memory skeleton 검증 자체는 ExtProc log의 `original_messages=1`, `mutated_messages=2`와 HTTP 200 유지 기준으로 판단했다.

## 결론

**검증 완료**

- custom Memory ExtProc image를 data plane에 적용할 수 있다.
- 기존 `/v1/chat/completions` 흐름은 HTTP 200을 유지했다.
- custom ExtProc에서 request body를 읽고 `messages` 배열을 조작할 수 있다.
- Redis 연동 전 dummy memory injection까지 확인했다.

## 다음 작업

**계획 / 검토 필요**

- Redis 배포
- `x-session-id` 기준 Redis key 설계 적용
- 첫 요청 후 Redis 저장
- 두 번째 요청에서 Redis history 조회
- dummy message 대신 실제 session history를 `messages` 앞에 병합

## 관련 raw log

```text
logs/v05-memory-extproc-skeleton-verify-2026-04-27.log
logs/v05-memory-extproc-skeleton-verify-final-2026-04-27.log
```
