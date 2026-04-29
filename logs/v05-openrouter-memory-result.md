# v0.5 OpenRouter + Redis Memory 검증 결과

상태: **검증 완료**

검증 일시: 2026-04-29

## 목적

OpenRouter 실제 LLM backend와 Redis 기반 Memory ExtProc를 함께 적용했을 때, session-based short-term memory가 자연어 응답에 반영되는지 확인한다.

## 검증 명령

```bash
./scripts/verify-openrouter-memory-v05.sh
```

## 구성

- Kubernetes context: `kind-aigw-v05`
- Backend: OpenRouter `openrouter.ai:443`
- Model: `google/gemini-2.0-flash-lite-001`
- Memory key: `memory:chat:demo-openrouter-memory-1`
- Session header: `x-session-id: demo-openrouter-memory-1`
- TTL: `3600` seconds
- ExtProc image: `envoy-ai-gateway-memory-extproc:v0.5.0-memory-skeleton`

## 결과

첫 번째 요청:

```text
내 이름은 홍길동입니다. 이 사실을 기억해줘.
```

응답:

```text
알겠습니다. 홍길동님, 당신의 이름은 홍길동이라는 것을 기억하겠습니다.
```

두 번째 요청:

```text
내 이름이 뭐야? 이름만 짧게 답해줘.
```

응답:

```text
홍길동
```

## Redis 저장 확인

```json
[
  {
    "role": "user",
    "content": "내 이름은 홍길동입니다. 이 사실을 기억해줘."
  },
  {
    "role": "assistant",
    "content": "알겠습니다. 홍길동님, 당신의 이름은 홍길동이라는 것을 기억하겠습니다. \n"
  },
  {
    "role": "user",
    "content": "내 이름이 뭐야? 이름만 짧게 답해줘."
  },
  {
    "role": "assistant",
    "content": "홍길동\n"
  }
]
```

TTL:

```text
3599
```

## 판단

**검증 완료**

- Redis에 session별 user/assistant history가 저장된다.
- 두 번째 요청에서 이전 history가 request body에 병합된다.
- OpenRouter 실제 LLM이 병합된 history를 보고 `홍길동`을 응답했다.
- 따라서 session-based short-term memory PoC의 end-to-end 흐름이 1차로 성립했다.

## 남은 검토

**검토 필요**

- 장기 메모리와 단기 메모리의 분리 설계
- Redis 장애 시 fallback 정책
- session id 누락 시 정책
- provider 비용 제한과 rate limit 대응
- 발표용 시연 스크립트 정리
