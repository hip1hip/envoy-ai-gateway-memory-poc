# v0.5 Redis Memory 검증 결과

## 상태

**검증 완료**

2026-04-29 기준 Kind `aigw-v05` 환경에서 Redis 기반 session memory 저장/조회/병합을 확인했다.

## 목적

Redis를 붙여 short-term memory 한 바퀴를 검증한다.

검증 항목:

- `x-session-id` 기준 Redis key 생성
- 첫 요청 후 user/assistant message 저장
- 두 번째 요청에서 Redis history 조회
- request `messages` 앞에 history 병합
- 응답 후 Redis history 갱신
- HTTP 200 유지

## Redis 배포

적용 manifest:

```text
manifests/v05/redis-memory.yaml
```

Redis 주소:

```text
redis://redis.ai-gateway-memory.svc.cluster.local:6379
```

## Memory ExtProc 설정

적용 manifest:

```text
manifests/v05/extproc-memory-redis-gateway-config.yaml
```

주요 환경변수:

```text
MEMORY_POC_REDIS_ENABLED=true
REDIS_URL=redis://redis.ai-gateway-memory.svc.cluster.local:6379
MEMORY_TTL_SECONDS=3600
MEMORY_MAX_HISTORY_MESSAGES=20
```

## 실행 명령

```bash
./scripts/build-memory-extproc-v05.sh
./scripts/verify-redis-memory-v05.sh
```

## 검증 시나리오

session id:

```text
demo-session-redis-1
```

첫 번째 요청:

```text
내 이름은 홍길동이야
```

Redis 저장 결과:

```json
[
  {"role":"user","content":"내 이름은 홍길동이야"},
  {"role":"assistant","content":"The quick brown fox jumps over the lazy dog."}
]
```

두 번째 요청:

```text
내 이름이 뭐야?
```

ExtProc log:

```text
memory poc merged redis history session_id=demo-session-redis-1 history_messages=2 request_messages=1 mutated_messages=3
```

최종 Redis 저장 결과:

```json
[
  {"role":"user","content":"내 이름은 홍길동이야"},
  {"role":"assistant","content":"The quick brown fox jumps over the lazy dog."},
  {"role":"user","content":"내 이름이 뭐야?"},
  {"role":"assistant","content":"I am the master of my fate."}
]
```

TTL:

```text
3599
```

## 결론

**검증 완료**

- Redis 저장/조회/history 병합이 동작했다.
- 두 번째 요청에서 이전 history가 request `messages`에 병합됐다.
- 전체 요청은 HTTP 200 OK를 유지했다.
- Redis key TTL도 설정됐다.

## 주의점

- 현재 backend는 test upstream이라 실제 LLM처럼 “홍길동입니다”라고 답하지 않는다.
- 이번 성공 기준은 자연어 응답이 아니라 Redis 저장/조회/병합과 HTTP 200 유지다.
- 실제 데모에서 “내 이름이 뭐야?”에 의미 있는 답을 보이려면 실제 LLM Provider 또는 memory-aware test backend가 필요하다.

## 관련 raw log

```text
logs/v05-redis-memory-verify-2026-04-29.log
```
