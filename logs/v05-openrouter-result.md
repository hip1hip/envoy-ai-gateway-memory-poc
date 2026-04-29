# v0.5 OpenRouter 실제 LLM 연동 결과

상태: **검증 완료**

검증 일시: 2026-04-29

## 목적

Envoy AI Gateway v0.5에서 test upstream이 아닌 실제 LLM provider인 OpenRouter를 backend로 연결할 수 있는지 확인한다.

## 적용한 구성

- Kubernetes context: `kind-aigw-v05`
- Backend: `openrouter.ai:443`
- TLS: `BackendTLSPolicy` `gateway.networking.k8s.io/v1`
- AIServiceBackend schema: `OpenAI`
- AIServiceBackend prefix: `/api/v1`
- Secret: `openrouter-api-key`
- Secret key name: `apiKey`
- Route match header: `x-ai-eg-model`
- 기본 검증 model: `google/gemini-2.0-flash-lite-001`

API key 값은 레포에 저장하지 않는다.

## 검증 명령

```bash
./scripts/verify-openrouter-v05.sh
```

## 검증 결과

```text
HTTP status: 200
Model: google/gemini-2.0-flash-lite-001
```

응답에는 OpenAI 호환 형식의 `choices` 필드가 포함되었다.

```json
{
  "object": "chat.completion",
  "model": "google/gemini-2.0-flash-lite-001",
  "provider": "Google",
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "Envoy AI Gateway를 통해 OpenRouter 호출이 성공적으로 이루어졌는지 확인하고 있습니다.\n"
      }
    }
  ],
  "usage": {
    "prompt_tokens": 25,
    "completion_tokens": 20,
    "total_tokens": 45,
    "cost": 0.000007875
  }
}
```

## 중간 실패와 원인

초기 시도에서는 `x-ai-eg-model: openrouter`로 요청했고, request body의 `model`은 `google/gemini-2.0-flash-lite-001`이었다.

결과:

```text
HTTP status: 404
No matching route found. It is likely because the model specified in your request is not configured in the Gateway.
```

원인:

- Envoy AI Gateway는 `x-ai-eg-model` route match 값과 요청 body의 `model` 값을 같은 모델 이름으로 맞춰야 정상 라우팅된다.
- 따라서 route match 값을 실제 모델 이름인 `google/gemini-2.0-flash-lite-001`로 수정했다.

## 다음 단계

**계획**

OpenRouter 실제 LLM backend와 Redis Memory ExtProc를 결합해 다음 시나리오를 검증한다.

1. 첫 요청: `내 이름은 홍길동입니다.`
2. Redis 저장 확인
3. 두 번째 요청: `내 이름이 뭐야?`
4. OpenRouter 응답이 이전 대화 내용을 반영하는지 확인
