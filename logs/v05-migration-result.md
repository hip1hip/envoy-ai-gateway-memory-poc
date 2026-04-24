# v0.5 Migration Result

## 상태

**검증 완료**

Envoy AI Gateway v0.5.0 환경을 별도 Kind 클러스터에 구성하고, v0.4 baseline source manifest를 그대로 적용했다. basic scenario 기준으로는 manifest 수정 없이 v0.5에서 정상 동작했다.

## 검증 환경

- Windows + WSL2 Ubuntu
- Docker Desktop
- Kind
- Kubernetes v1.32.0
- Envoy Gateway v1.6.0
- Envoy AI Gateway v0.5.0
- v0.4 baseline manifest: `manifests/v04/basic.yaml`
- v0.5 migrated manifest: `manifests/v05/basic-migrated.yaml`

검증용 clone 경로:

```bash
/home/hip1h/workspace/envoy-ai-gateway-memory-poc-v05-verify-20260424-155638
```

## setup-v05.sh 실행 결과

실행:

```bash
./scripts/setup-v05.sh
```

결과:

```text
Creating cluster "aigw-v05" ...
Set kubectl context to "kind-aigw-v05"
Envoy Gateway v1.6.0 설치 성공
Envoy AI Gateway v0.5.0 CRD 설치 성공
Envoy AI Gateway v0.5.0 controller 설치 성공
v0.5 환경에 v0.4 source manifest 적용 성공
```

v0.4 source manifest 적용 결과:

```text
gatewayclass.gateway.networking.k8s.io/envoy-ai-gateway-basic created
gateway.gateway.networking.k8s.io/envoy-ai-gateway-basic created
clienttrafficpolicy.gateway.envoyproxy.io/client-buffer-limit created
aigatewayroute.aigateway.envoyproxy.io/envoy-ai-gateway-basic created
aiservicebackend.aigateway.envoyproxy.io/envoy-ai-gateway-basic-testupstream created
backend.gateway.envoyproxy.io/envoy-ai-gateway-basic-testupstream created
deployment.apps/envoy-ai-gateway-basic-testupstream created
service/envoy-ai-gateway-basic-testupstream created
envoyproxy.gateway.envoyproxy.io/envoy-ai-gateway-basic created
```

## verify-v05.sh 실행 결과

실행:

```bash
./scripts/verify-v05.sh
```

주요 결과:

```text
aigw-v05-control-plane   Ready   control-plane   v1.32.0
envoy-gateway-...        1/1     Running
ai-gateway-controller-... 1/1     Running
AIGatewayRoute           Accepted
AIServiceBackend         Accepted
gatewayconfigs.aigateway.envoyproxy.io 존재
```

Gateway 요약:

```text
gateway.gateway.networking.k8s.io/envoy-ai-gateway-basic   envoy-ai-gateway-basic   PROGRAMMED=False
```

Kind 환경 특성상 외부 address가 없어 top-level `PROGRAMMED=False`가 보인다. `describe gateway` 기준 Listener 조건은 정상이다.

```text
Listener Programmed=True
Listener Accepted=True
Listener ResolvedRefs=True
```

## Data plane 상태

초기에는 Envoy data plane Pod가 `ContainerCreating`이었다. 잠시 대기 후 다음 상태를 확인했다.

```text
envoy-default-envoy-ai-gateway-basic-21a9f8f8-78bb85449b-2mjjc   3/3   Running
envoy-gateway-54cd886ccc-q9pd4                                   1/1   Running
```

## migrated manifest 적용

v0.4 source manifest와 v0.5 upstream basic manifest가 동일했기 때문에 `manifests/v05/basic-migrated.yaml`은 동일 파일로 고정했다.

적용:

```bash
kubectl apply -f manifests/v05/basic-migrated.yaml
```

결과:

```text
gatewayclass.gateway.networking.k8s.io/envoy-ai-gateway-basic unchanged
gateway.gateway.networking.k8s.io/envoy-ai-gateway-basic configured
clienttrafficpolicy.gateway.envoyproxy.io/client-buffer-limit unchanged
aigatewayroute.aigateway.envoyproxy.io/envoy-ai-gateway-basic configured
aiservicebackend.aigateway.envoyproxy.io/envoy-ai-gateway-basic-testupstream unchanged
backend.gateway.envoyproxy.io/envoy-ai-gateway-basic-testupstream unchanged
deployment.apps/envoy-ai-gateway-basic-testupstream unchanged
service/envoy-ai-gateway-basic-testupstream unchanged
envoyproxy.gateway.envoyproxy.io/envoy-ai-gateway-basic unchanged
```

## curl 검증 결과

port-forward:

```bash
kubectl port-forward -n envoy-gateway-system svc/envoy-default-envoy-ai-gateway-basic-21a9f8f8 18080:80
```

성공:

```text
Forwarding from 127.0.0.1:18080 -> 10080
Forwarding from [::1]:18080 -> 10080
```

curl:

```bash
curl -sS -i \
  -H "Content-Type: application/json" \
  -H "x-ai-eg-model: some-cool-self-hosted-model" \
  --data @request-v05.json \
  http://localhost:18080/v1/chat/completions
```

응답:

```http
HTTP/1.1 200 OK
content-type: application/json
testupstream-id: test
x-model: some-cool-self-hosted-model
```

body:

```json
{
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "To be or not to be, that is the question."
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

## Migration 판단

**검증 완료**

basic scenario 기준 v0.4에서 v0.5로의 manifest migration은 no-op이다.

- v0.4.0 `examples/basic/basic.yaml`과 v0.5.0 `examples/basic/basic.yaml`은 동일하다.
- v0.4 source manifest는 v0.5 CRD/controller 환경에서 apply error 없이 생성된다.
- `AIGatewayRoute`와 `AIServiceBackend`는 Accepted 상태다.
- curl 요청은 HTTP 200 OK를 반환한다.

## 남은 검토 필요 항목

- `GatewayConfig`를 실제 Gateway에 붙였을 때 extProc env/resources가 반영되는지
- `schema.version` 사용 manifest를 만들어 v0.5에서 deprecated behavior를 확인할지 여부
- `schema.prefix` 기반 provider/backend manifest 작성
- Body Mutation 동작 검증
- Header Mutation 동작 검증
- Memory PoC에서 ExtProc를 통해 request/response body를 다루는 방식 검증

## 검증 중 발생한 트러블

1. PowerShell here-string을 WSL Bash로 넘길 때 BOM 때문에 `set: command not found` 경고가 한 번 발생했다.
   - clone은 정상 완료됐다.
   - 후속 자동화는 WSL 내부 Bash 파일 실행 방식이 안전하다.

2. PowerShell에서 생성한 Bash 파일이 CRLF로 저장되어 `tee` 결과 파일명이 `curl-v05-response.log\r`로 생성됐다.
   - 원인: CRLF line ending
   - 조치: 파일명을 정상 이름으로 변경했다.
   - 레포의 공식 `scripts/*.sh`는 `.gitattributes`와 실행 비트로 LF를 유지한다.

## 원본 로그

- `logs/v05-setup-script-run-2026-04-24.log`
- `logs/v05-verify-script-run-2026-04-24.log`
- `logs/v05-dataplane-wait-2026-04-24.log`
- `logs/v05-apply-migrated-2026-04-24.log`
- `logs/v05-port-forward-2026-04-24.log`
- `logs/v05-curl-response-2026-04-24.log`
- `logs/v05-resource-summary-2026-04-24.log`
- `logs/v05-describe-gateway-2026-04-24.log`
- `logs/v05-describe-aigatewayroute-2026-04-24.log`
- `logs/v05-describe-aiservicebackend-2026-04-24.log`
