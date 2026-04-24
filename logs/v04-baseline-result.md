# v0.4 Baseline Result

## 상태

**검증 완료**

Envoy AI Gateway v0.4.0 basic example을 Kind Kubernetes v1.32.0 환경에서 실행하고, port-forward 기반 curl 요청으로 HTTP 200 OK 응답을 확인했다.

## 검증 환경

- Windows + WSL2 Ubuntu
- Docker Desktop
- Kind
- Kubernetes v1.32.0
- Envoy Gateway v1.5.4
- Envoy AI Gateway v0.4.0
- Envoy AI Gateway v0.4.0 태그의 `examples/basic/basic.yaml`

## 성공 기준

- Kubernetes node Ready
- Envoy Gateway Pod Running
- AI Gateway Controller Pod Running
- Envoy data plane Pod Running
- AIGatewayRoute Accepted
- AIServiceBackend Accepted
- `/v1/chat/completions` 요청 HTTP 200 OK

## 성공 응답

```http
HTTP/1.1 200 OK
content-type: application/json
testupstream-id: test
x-model: some-cool-self-hosted-model
```

```json
{
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "The quick brown fox jumps over the lazy dog."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 1,
    "completion_tokens": 100,
    "total_tokens": 300
  }
}
```

## 참고

자세한 재현 절차는 [docs/01-v04-baseline.md](../docs/01-v04-baseline.md)를 기준으로 한다.
