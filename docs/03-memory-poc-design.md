# Memory PoC Design

이 문서는 구현 전 설계 초안이다. 내용은 **계획** 또는 **검토 필요** 상태이며, v0.5 환경에서 실제 검증이 필요하다.

## 목표

session-based short-term memory를 Envoy AI Gateway 앞단 또는 확장 지점에서 제공한다. 특정 앱에만 종속된 memory가 아니라, 플랫폼 레벨에서 여러 서비스가 공통으로 사용할 수 있는 범용 Inference API 기능을 목표로 한다.

## 핵심 요구사항

- `x-session-id` 헤더로 세션을 구분한다.
- Redis에 세션별 message history를 저장한다.
- 최근 N개 메시지만 유지한다.
- sliding window 방식으로 오래된 메시지를 제거한다.
- TTL로 비활성 세션을 만료한다.
- OpenAI compatible `/v1/chat/completions` 요청을 우선 대상으로 한다.
- MCP와 Agent Gateway는 이번 핵심 범위에서 제외한다.

## 데이터 모델 초안

**계획**

Redis key:

```text
memory:chat:{session_id}
```

value:

```json
[
  {
    "role": "user",
    "content": "내 이름은 홍길동이야"
  },
  {
    "role": "assistant",
    "content": "안녕하세요, 홍길동님."
  }
]
```

정책:

- `MAX_HISTORY_MESSAGES`: 최근 N개 메시지 유지
- `MEMORY_TTL_SECONDS`: 세션 TTL
- 저장 형식은 OpenAI compatible `messages` 배열과 맞춘다.
- 너무 긴 content나 대용량 tool payload는 별도 제한이 필요하다.

## Request Path

**계획**

```text
Client
  -> Envoy AI Gateway
  -> ExtProc
  -> Redis
  -> LLM/Test Backend
```

요청 처리 순서:

1. Client가 `/v1/chat/completions`로 요청한다.
2. Client가 `x-session-id` 헤더를 전달한다.
3. Envoy AI Gateway가 요청을 수신한다.
4. ExtProc가 `x-session-id`를 읽는다.
5. ExtProc가 Redis에서 세션 history를 조회한다.
6. ExtProc가 기존 `messages` 앞에 최근 history를 병합한다.
7. Envoy AI Gateway가 병합된 요청을 LLM/Test Backend로 전달한다.

## Response Path

**계획**

```text
LLM/Test Backend
  -> Envoy AI Gateway
  -> ExtProc
  -> Redis 저장
  -> Client
```

응답 처리 순서:

1. LLM/Test Backend가 assistant 응답을 반환한다.
2. ExtProc가 response body에서 assistant message를 추출한다.
3. ExtProc가 요청의 user message와 응답의 assistant message를 Redis에 저장한다.
4. Redis key에 TTL을 갱신한다.
5. Redis list 또는 JSON array를 최근 N개 메시지만 유지한다.
6. Client에 원래 응답을 반환한다.

## Option A: ExtProc 기반 Memory

**계획 / 우선 검토 후보**

ExtProc가 memory orchestration을 담당한다.

```text
Client
  -> Envoy AI Gateway
  -> Memory ExtProc
  -> Redis
  -> Envoy AI Gateway
  -> LLM/Test Backend
```

장점:

- 클라이언트는 `x-session-id`만 전달하면 된다.
- Memory 정책을 플랫폼 레벨에서 일관되게 적용할 수 있다.
- request/response 양쪽에서 Redis 연계가 가능하다.
- `messages` 배열 내부 조작처럼 복잡한 JSON 처리를 코드로 다룰 수 있다.

검토 필요:

- request body 전체 읽기와 mutation 가능 여부
- response body 읽기와 저장 가능 여부
- body buffering 크기 제한
- ExtProc 장애 시 요청 실패 정책
- Redis 장애 시 정책

검증 완료:

- v0.5 `GatewayConfig`의 `spec.extProc.kubernetes.env`를 통해 `REDIS_URL`, `MEMORY_TTL_SECONDS`, `MEMORY_MAX_HISTORY_MESSAGES` 같은 Memory 설정을 `ai-gateway-extproc` 컨테이너에 전달할 수 있다.
- v0.5 `GatewayConfig`의 `spec.extProc.kubernetes.resources`를 통해 ExtProc 컨테이너 requests/limits를 설정할 수 있다.
- 단, 기존 data plane Pod에는 즉시 반영되지 않았고 rollout restart 후 새 Pod에서 반영을 확인했다.

## Option B: Body Mutation + 외부 Memory Service

**계획 / fallback 후보**

Body Mutation과 외부 Memory Service를 조합한다.

```text
Client
  -> Memory Service에서 history 조회
  -> Client가 messages 병합
  -> Envoy AI Gateway
  -> LLM/Test Backend
  -> Client
  -> Memory Service에 결과 저장
```

또는 Gateway 설정에서 Body Mutation으로 top-level field를 보정하고, 실제 history 조회/저장은 별도 Memory Service가 담당한다.

장점:

- ExtProc 구현 복잡도를 줄일 수 있다.
- Gateway의 v0.5 기능을 빠르게 검증할 수 있다.
- Memory Service를 일반 REST API로 구현할 수 있다.

단점:

- 클라이언트 책임이 커진다.
- 플랫폼 레벨 공통 기능으로 보기 어렵다.
- Body Mutation이 top-level field만 지원한다면 `messages` 전체 교체 외의 세밀한 조작이 어렵다.
- response 저장을 Gateway 레벨에서 자동화하기 어렵다.

## 왜 MCP는 핵심 범위가 아닌가

MCP는 tool/agent 생태계와 연결되는 확장 지점이다. 이번 PoC의 핵심은 Inference API 자체에 short-term memory capability를 붙일 수 있는지 확인하는 것이다.

따라서 MCP는 다음 이유로 optional로 둔다.

- 기본 chat completions memory 구현에 필수 요소가 아니다.
- Agent tool 호출 memory와 일반 LLM session memory는 책임이 다르다.
- 2주 PoC 범위에서는 v0.5 migration과 memory 핵심 흐름 검증이 우선이다.

## 왜 Agent Gateway는 제외하는가

Agent Gateway 확장은 agent runtime, tool routing, agent protocol에 가까운 문제다. 현재 목표는 특정 agent framework가 아니라 사내 플랫폼의 범용 Inference API 기능이다.

따라서 이번 범위에서는 Envoy AI Gateway와 Memory layer 사이의 연계를 먼저 검증한다.

## 범용 플랫폼 설계 원칙

- 특정 앱의 user id, workspace id, domain model에 의존하지 않는다.
- 공통 식별자는 `x-session-id`부터 시작한다.
- memory 저장 정책은 플랫폼 설정으로 제어한다.
- 클라이언트가 memory 동작을 알 필요를 최소화한다.
- 장애 정책은 명확해야 한다.
  - memory 조회 실패 시 요청을 실패시킬지
  - memory 없이 LLM 호출을 진행할지
  - 장애를 응답 헤더나 metric으로 노출할지
- 민감 정보 저장 가능성이 있으므로 TTL, 최대 길이, logging 정책을 제한한다.

## 기본 검증 시나리오

**계획**

1. 동일 `x-session-id`로 첫 요청을 보낸다.
2. assistant 응답이 Redis에 저장되는지 확인한다.
3. 동일 `x-session-id`로 두 번째 요청을 보낸다.
4. 두 번째 요청에 이전 history가 주입되는지 확인한다.
5. 다른 `x-session-id` 요청과 history가 섞이지 않는지 확인한다.
6. N개를 초과하는 메시지가 sliding window로 제거되는지 확인한다.
7. TTL 이후 Redis key가 만료되는지 확인한다.

## 미검증 항목

다음은 모두 **검토 필요**다.

- v0.5 ExtProc에서 request/response body를 모두 mutation 또는 inspect할 수 있는지
- Body Mutation만으로 memory injection을 충분히 구현할 수 있는지
- Redis 장애 시 Gateway가 어떤 방식으로 실패하는 것이 적절한지
- OpenAI compatible streaming response에서 memory 저장을 어떻게 처리할지
- multi-provider routing에서 provider별 schema 차이를 어떻게 다룰지
