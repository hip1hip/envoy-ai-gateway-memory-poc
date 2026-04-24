# Envoy AI Gateway v0.4 Baseline

## 목적

Envoy AI Gateway v0.4.0 basic example을 로컬 Kubernetes 환경에서 재현하고, `/v1/chat/completions` 요청이 Envoy AI Gateway를 통해 test backend까지 정상 라우팅되는지 확인한다.

이 문서의 v0.4 baseline 내용은 **검증 완료** 상태다.

## 환경

**검증 완료**

- Windows + WSL2 Ubuntu
- Docker Desktop
- Kind
- Kubernetes v1.32.0
- Envoy Gateway v1.5.4
- Envoy AI Gateway v0.4.0
- Envoy AI Gateway v0.4.0 태그의 `examples/basic/basic.yaml`

## 사전 준비 도구

다음 도구가 WSL2 Ubuntu에서 실행 가능해야 한다.

```bash
docker version
docker ps
kind version
kubectl version --client
helm version
curl --version
```

명령어 역할:

- `docker version`: WSL2에서 Docker Desktop daemon과 통신 가능한지 확인한다.
- `docker ps`: Docker daemon 접근 권한과 현재 container 조회 가능 여부를 확인한다.
- `kind version`: Kind 설치 여부를 확인한다.
- `kubectl version --client`: kubectl client 설치 여부를 확인한다.
- `helm version`: Helm 설치 여부를 확인한다.
- `curl --version`: HTTP 검증 도구 설치 여부를 확인한다.

## Kind 클러스터 생성

처음에는 다음 명령으로 클러스터를 생성했다.

```bash
kind create cluster --name aigw-v04
```

하지만 기본 Kubernetes v1.35.x가 잡혀 Envoy Gateway v1.5.x와의 호환성 문제가 의심되었다.

따라서 Kubernetes v1.32.0을 명시해서 재생성했다.

```bash
kind delete cluster --name aigw-v04
kind create cluster --name aigw-v04 --image kindest/node:v1.32.0
kubectl config use-context kind-aigw-v04
kubectl get nodes -o wide
```

성공 확인:

```text
aigw-v04-control-plane   Ready   control-plane   v1.32.0
```

역할:

- `kind create cluster`: 로컬 Docker 위에 Kubernetes cluster를 생성한다.
- `--image kindest/node:v1.32.0`: Kubernetes node image 버전을 고정한다.
- `kubectl config use-context`: kubectl 대상 cluster를 명시한다.
- `kubectl get nodes -o wide`: node 상태와 Kubernetes 버전을 확인한다.

## Envoy Gateway 설치

```bash
helm upgrade -i eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.5.4 \
  --namespace envoy-gateway-system \
  --create-namespace \
  -f https://raw.githubusercontent.com/envoyproxy/ai-gateway/v0.4.0/manifests/envoy-gateway-values.yaml
```

상태 확인:

```bash
kubectl wait --timeout=3m -n envoy-gateway-system \
  deployment/envoy-gateway \
  --for=condition=Available

kubectl get pods -n envoy-gateway-system
```

역할:

- `helm upgrade -i`: release가 없으면 설치하고, 있으면 업그레이드한다.
- `--version v1.5.4`: Envoy Gateway Helm chart 버전을 고정한다.
- `-f .../v0.4.0/.../envoy-gateway-values.yaml`: v0.4.0 AI Gateway 예제와 맞는 Envoy Gateway values를 사용한다.
- `kubectl wait`: controller deployment가 사용 가능한 상태가 될 때까지 대기한다.

## Envoy AI Gateway v0.4 설치

CRD 설치:

```bash
helm upgrade -i aieg-crd oci://docker.io/envoyproxy/ai-gateway-crds-helm \
  --version v0.4.0 \
  --namespace envoy-ai-gateway-system \
  --create-namespace
```

Controller 설치:

```bash
helm upgrade -i aieg oci://docker.io/envoyproxy/ai-gateway-helm \
  --version v0.4.0 \
  --namespace envoy-ai-gateway-system \
  --create-namespace
```

상태 확인:

```bash
kubectl wait --timeout=3m -n envoy-ai-gateway-system \
  deployment/ai-gateway-controller \
  --for=condition=Available

kubectl get pods -n envoy-ai-gateway-system
```

성공 확인:

```text
ai-gateway-controller-...   1/1   Running
```

## v0.4 basic example 적용

main 브랜치 raw URL을 사용하면 최신 스키마 기준 manifest가 내려올 수 있으므로 v0.4 baseline에서는 사용하지 않는다.

잘못된 패턴:

```text
GitHub raw URL에서 branch 위치에 main을 넣는 형태
```

관찰된 오류:

```text
no matches for kind "AIGatewayRoute" in version "aigateway.envoyproxy.io/v1beta1"
no matches for kind "AIServiceBackend" in version "aigateway.envoyproxy.io/v1beta1"
ensure CRDs are installed first
```

해결:

```bash
cd ~/workspace
git clone --branch v0.4.0 https://github.com/envoyproxy/ai-gateway.git ai-gateway-v04
cd ai-gateway-v04
kubectl apply -f examples/basic/basic.yaml
```

v0.4 basic example에 포함된 주요 kind:

```text
GatewayClass
Gateway
ClientTrafficPolicy
AIGatewayRoute
AIServiceBackend
Backend
Deployment
Service
EnvoyProxy
```

AI Gateway CRD 확인:

```bash
kubectl get crd | grep -i ai
```

확인된 주요 CRD:

```text
aigatewayroutes.aigateway.envoyproxy.io
aiservicebackends.aigateway.envoyproxy.io
backendsecuritypolicies.aigateway.envoyproxy.io
mcproutes.aigateway.envoyproxy.io
```

## Gateway / Route / Backend 상태 확인

```bash
kubectl get gateway
kubectl describe gateway envoy-ai-gateway-basic
kubectl get aigatewayroute
kubectl describe aigatewayroute envoy-ai-gateway-basic
kubectl get aiservicebackend
kubectl describe aiservicebackend envoy-ai-gateway-basic-testupstream
kubectl get pods -n envoy-gateway-system
```

관찰 결과:

- `kubectl get gateway`에서는 `PROGRAMMED=False`로 보였다.
- `kubectl describe gateway envoy-ai-gateway-basic`의 Listener 조건은 정상이다.
  - `Programmed=True`
  - `Accepted=True`
  - `ResolvedRefs=True`
- `AIGatewayRoute`는 `Accepted` 상태다.
- `AIServiceBackend`는 `Accepted` 상태다.
- Envoy Gateway Pod는 `1/1 Running` 상태다.
- Envoy data plane Pod는 `3/3 Running` 상태다.

판단:

- Kind 로컬 환경에서는 Gateway에 외부 ADDRESS가 자동 할당되지 않아 `PROGRAMMED=False`로 보일 수 있다.
- Listener와 AIGatewayRoute, AIServiceBackend가 정상 상태이므로 port-forward 기반 검증을 진행할 수 있다.

## port-forward

Envoy data plane Service 이름을 조회한다.

```bash
export ENVOY_SERVICE=$(kubectl get svc -n envoy-gateway-system \
  --selector=gateway.envoyproxy.io/owning-gateway-namespace=default,gateway.envoyproxy.io/owning-gateway-name=envoy-ai-gateway-basic \
  -o jsonpath='{.items[0].metadata.name}')

echo "$ENVOY_SERVICE"
```

별도 터미널에서 port-forward를 실행한다.

```bash
kubectl port-forward -n envoy-gateway-system svc/$ENVOY_SERVICE 8080:80
```

성공 확인:

```text
Forwarding from 127.0.0.1:8080 -> 10080
Forwarding from [::1]:8080 -> 10080
```

## curl 테스트

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

실제 성공 응답:

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

## Baseline 성공 기준

**검증 완료**

- Kubernetes node가 `Ready` 상태다.
- Envoy Gateway Pod가 `Running` 상태다.
- AI Gateway Controller Pod가 `Running` 상태다.
- v0.4 basic example의 Envoy data plane Pod가 `Running` 상태다.
- `AIGatewayRoute`가 `Accepted` 상태다.
- `AIServiceBackend`가 `Accepted` 상태다.
- `/v1/chat/completions` 요청에 대해 HTTP `200 OK`를 받는다.

## 검증 완료와 추정 구분

### 검증 완료

- WSL2 Ubuntu에서 Docker Desktop 연동
- Kind Kubernetes v1.32.0 기반 v0.4 baseline 구성
- Envoy Gateway v1.5.4 설치
- Envoy AI Gateway v0.4.0 설치
- v0.4.0 태그의 basic example 적용
- port-forward 기반 curl 성공

### 추정 / 검토 필요

- Kind 기본 Kubernetes v1.35.x와 Envoy Gateway v1.5.x 사이의 정확한 호환성 원인
- `kubectl get gateway`의 `PROGRAMMED=False`가 Kind 환경의 외부 ADDRESS 미할당만으로 발생하는지에 대한 공식 조건 확인
- v0.5에서 동일 basic scenario가 어떤 manifest 변경을 요구하는지
