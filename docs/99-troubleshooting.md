# Troubleshooting

## WSL2에서 `docker: command not found`

증상:

```text
docker: command not found
```

확인:

```bash
which docker
docker version
```

대응:

- Docker Desktop이 설치되어 있는지 확인한다.
- Docker Desktop 설정에서 WSL integration이 활성화되어 있는지 확인한다.
- Ubuntu terminal을 새로 열고 다시 확인한다.

예상 결과:

```bash
docker version
docker ps
```

두 명령이 모두 성공해야 Kind 클러스터를 생성할 수 있다.

## Docker Desktop 중지로 인한 Kind API 연결 실패

증상:

```text
The system cannot find the file specified.
Unable to connect to the server: dial tcp 127.0.0.1:<port>: connectex: No connection could be made
```

가능한 원인:

- Docker Desktop이 실행 중이 아니다.
- WSL Docker integration이 준비되기 전에 `kubectl` 또는 `kind` 명령을 실행했다.
- 기존 Kind cluster container는 남아 있지만 Kubernetes API server에 연결할 수 없다.

확인:

```bash
docker version
kind get clusters
kubectl --context kind-aigw-v05 get nodes
```

대응:

- Windows에서 Docker Desktop을 실행한다.
- WSL terminal을 새로 열고 `docker version`이 성공하는지 확인한다.
- 이후 `kind get clusters`, `kubectl get nodes` 순서로 cluster 상태를 다시 확인한다.

예상 결과:

```text
aigw-v05-control-plane   Ready
```

## Kind 기본 Kubernetes v1.35.x 사용 문제

증상:

- `kind create cluster --name aigw-v04`만 실행했을 때 예상보다 높은 Kubernetes 버전이 사용된다.
- Envoy Gateway v1.5.x와 호환성 문제가 의심된다.

확인:

```bash
kubectl get nodes -o wide
```

대응:

v0.4 baseline에서는 Kubernetes v1.32.0을 명시한다.

```bash
kind create cluster --name aigw-v04 --image kindest/node:v1.32.0
```

기존 클러스터 삭제가 필요하면 먼저 대상 이름을 확인하고 직접 판단한다.

```bash
kind get clusters
kind delete cluster --name aigw-v04
```

## main 브랜치 example 사용 문제

증상:

GitHub raw URL에서 branch 위치에 `main`을 넣는 형태를 사용하면 v0.4 CRD와 맞지 않는 manifest가 적용될 수 있다.

대응:

v0.4 baseline에서는 반드시 v0.4.0 태그를 사용한다.

```bash
git clone --branch v0.4.0 https://github.com/envoyproxy/ai-gateway.git ai-gateway-v04
cd ai-gateway-v04
kubectl apply -f examples/basic/basic.yaml
```

## `AIGatewayRoute`, `AIServiceBackend` no matches 에러

증상:

```text
no matches for kind "AIGatewayRoute" in version "aigateway.envoyproxy.io/v1beta1"
no matches for kind "AIServiceBackend" in version "aigateway.envoyproxy.io/v1beta1"
ensure CRDs are installed first
```

가능한 원인:

- AI Gateway CRD가 설치되지 않았다.
- 설치한 CRD 버전과 example manifest 버전이 맞지 않는다.
- main 브랜치 example을 v0.4 환경에 적용했다.

확인:

```bash
kubectl get crd | grep -i ai
helm list -n envoy-ai-gateway-system
```

대응:

```bash
helm upgrade -i aieg-crd oci://docker.io/envoyproxy/ai-gateway-crds-helm \
  --version v0.4.0 \
  --namespace envoy-ai-gateway-system \
  --create-namespace

helm upgrade -i aieg oci://docker.io/envoyproxy/ai-gateway-helm \
  --version v0.4.0 \
  --namespace envoy-ai-gateway-system \
  --create-namespace
```

그 다음 v0.4.0 태그의 example을 적용한다.

## Gateway `PROGRAMMED=False` 해석

증상:

```bash
kubectl get gateway
```

출력에서 `PROGRAMMED=False`로 보인다.

확인:

```bash
kubectl describe gateway envoy-ai-gateway-basic
```

Listener 조건을 확인한다.

확인할 조건:

- `Accepted=True`
- `ResolvedRefs=True`
- `Programmed=True`

판단:

- Kind 로컬 환경에서는 외부 LoadBalancer ADDRESS가 자동 할당되지 않아 `kubectl get gateway`에서 `PROGRAMMED=False`로 보일 수 있다.
- Listener 조건과 route/backend 상태가 정상이라면 port-forward 기반 검증을 진행할 수 있다.

## Kind 환경에서 외부 ADDRESS 미할당

증상:

```bash
kubectl get gateway
kubectl get svc -n envoy-gateway-system
```

외부 IP나 ADDRESS가 비어 있다.

대응:

Kind에서는 LoadBalancer 외부 주소가 자동으로 붙지 않는 것이 일반적이다. 로컬 검증은 port-forward로 진행한다.

```bash
export ENVOY_SERVICE=$(kubectl get svc -n envoy-gateway-system \
  --selector=gateway.envoyproxy.io/owning-gateway-namespace=default,gateway.envoyproxy.io/owning-gateway-name=envoy-ai-gateway-basic \
  -o jsonpath='{.items[0].metadata.name}')

kubectl port-forward -n envoy-gateway-system svc/$ENVOY_SERVICE 8080:80
```

## `curl: connection refused`

증상:

```text
curl: (7) Failed to connect to localhost port 8080
```

가능한 원인:

- port-forward를 실행하지 않았다.
- port-forward가 종료되었다.
- 다른 터미널에서 port-forward를 실행했지만 에러로 중단되었다.
- 로컬 8080 포트를 다른 프로세스가 사용 중이다.

확인:

```bash
kubectl get svc -n envoy-gateway-system
kubectl get pods -n envoy-gateway-system
```

대응:

별도 터미널에서 다시 실행한다.

```bash
kubectl port-forward -n envoy-gateway-system svc/$ENVOY_SERVICE 8080:80
```

성공 메시지:

```text
Forwarding from 127.0.0.1:8080 -> 10080
Forwarding from [::1]:8080 -> 10080
```

## `./scripts/setup-v04.sh: Permission denied`

증상:

```text
./scripts/setup-v04.sh: Permission denied
```

가능한 원인:

- Git checkout 이후 script 실행 비트가 없다.
- Windows에서 작성한 파일이 WSL에서 executable로 표시되지 않는다.

확인:

```bash
ls -l scripts/*.sh
```

대응:

```bash
chmod +x scripts/setup-v04.sh scripts/verify-v04.sh scripts/cleanup-v04.sh
./scripts/setup-v04.sh
```

또는 실행 비트와 무관하게 Bash로 직접 실행한다.

```bash
bash scripts/setup-v04.sh
```

예상 결과:

- 스크립트가 사전 도구 확인부터 진행된다.

## `Unable to listen on port 8080`

증상:

```text
Unable to listen on port 8080
bind: address already in use
```

가능한 원인:

- 기존 `kubectl port-forward` 프로세스가 이미 8080을 사용 중이다.
- 다른 로컬 개발 서버가 8080을 사용 중이다.

확인:

```bash
ps -ef | grep kubectl | grep port-forward
ss -ltnp | grep ':8080'
```

대응:

- 기존 port-forward가 같은 Envoy Service를 가리키면 그대로 재사용한다.
- 다른 프로세스가 사용 중이면 다른 로컬 포트를 사용한다.

예:

```bash
kubectl port-forward -n envoy-gateway-system svc/$ENVOY_SERVICE 18080:80
```

curl도 같은 포트로 변경한다.

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
  http://localhost:18080/v1/chat/completions
```

## PowerShell에서 WSL Bash 명령 quote가 깨짐

증상:

- Bash 변수 예: `$VERIFY_DIR`가 비어 있는 것처럼 보인다.
- JSON body가 PowerShell에서 먼저 해석되어 `unexpected EOF` 또는 `Unexpected token ':'`가 발생한다.

원인:

- PowerShell과 Bash의 quoting 규칙이 다르다.
- WSL로 복잡한 multi-line 명령을 넘길 때 PowerShell이 `$`, quote, JSON 문자를 먼저 해석할 수 있다.

대응:

- WSL 안에서 직접 Bash shell을 열고 명령을 실행한다.
- 복잡한 JSON body는 inline으로 넘기지 말고 파일로 분리한다.

예:

```bash
cat > request-v04.json <<'JSON'
{
  "model": "some-cool-self-hosted-model",
  "messages": [
    {
      "role": "system",
      "content": "Hi."
    }
  ]
}
JSON

curl -i \
  -H "Content-Type: application/json" \
  -H "x-ai-eg-model: some-cool-self-hosted-model" \
  --data @request-v04.json \
  http://localhost:8080/v1/chat/completions
```

## PowerShell에서 만든 Bash 파일의 CRLF 문제

증상:

- WSL에서 Bash 파일은 실행되지만 `tee` 결과 파일명이 `curl-v05-response.log\r`처럼 생성된다.
- 또는 `set: command not found` 같은 이상한 메시지가 첫 줄에서 발생한다.

가능한 원인:

- PowerShell `Set-Content`가 CRLF line ending으로 파일을 저장했다.
- here-string 앞에 BOM이 들어갔다.

확인:

```bash
ls -lb
```

대응:

```bash
dos2unix run-v05-curl.sh
```

`dos2unix`가 없다면 WSL 내부에서 파일을 다시 생성한다.

```bash
cat > run-v05-curl.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF
```

이미 `\r`이 포함된 파일명이 생겼다면 이름을 정리한다.

```bash
mv $'curl-v05-response.log\r' curl-v05-response.log
```

## GatewayConfig Accepted이지만 ExtProc env/resources가 비어 있음

증상:

```bash
kubectl describe gatewayconfig memory-poc-gateway-config
```

에서는 `Accepted=True`로 보이지만, data plane Pod의 `ai-gateway-extproc` 컨테이너 env/resources가 비어 있다.

확인:

```bash
POD=$(kubectl get pods -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=envoy-ai-gateway-basic \
  --sort-by=.metadata.creationTimestamp \
  --no-headers | awk '$3 == "Running" { pod_name=$1 } END { print pod_name }')

kubectl get pod "$POD" -n envoy-gateway-system \
  -o jsonpath='{range .spec.containers[?(@.name=="ai-gateway-extproc")].env[*]}{.name}={.value}{"\n"}{end}'

kubectl get pod "$POD" -n envoy-gateway-system \
  -o jsonpath='{.spec.containers[?(@.name=="ai-gateway-extproc")].resources}{"\n"}'
```

대응:

GatewayConfig를 적용하고 Gateway annotation을 연결한 뒤 data plane Deployment를 재시작한다.

```bash
DEPLOYMENT=$(kubectl get deployment -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=envoy-ai-gateway-basic \
  -o jsonpath='{.items[0].metadata.name}')

kubectl rollout restart deployment "$DEPLOYMENT" -n envoy-gateway-system
kubectl rollout status deployment "$DEPLOYMENT" -n envoy-gateway-system --timeout=3m
```

예상 결과:

- 새 data plane Pod가 생성된다.
- `ai-gateway-extproc` 컨테이너 env에 `MEMORY_POC_MARKER=gateway-config-v05`가 보인다.
- resources에 requests/limits가 보인다.

## custom ExtProc가 `config version mismatch`로 CrashLoopBackOff

증상:

```text
failed to load initial config: config version mismatch: expected "dev", got "v0.5.0"
```

가능한 원인:

- Envoy AI Gateway extProc binary를 직접 `go build`로 빌드하면서 version ldflags를 넣지 않았다.
- binary가 `dev` version으로 실행되고, controller가 생성한 config는 `v0.5.0` version이라 mismatch가 발생한다.

대응:

v0.5.0 tag 기준으로 build할 때 version 값을 주입한다.

```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build \
  -ldflags '-X github.com/envoyproxy/ai-gateway/internal/version.version=v0.5.0-0-gb40501fe' \
  -o out/extproc-linux-amd64 \
  ./cmd/extproc
```

예상 결과:

- ExtProc log의 version이 `v0.5.0`으로 표시된다.
- config watcher가 정상 시작된다.

## `x-ai-eg-model` 헤더 누락

증상:

- route match가 실패한다.
- 예상한 backend로 라우팅되지 않는다.
- HTTP 404 또는 5xx 응답이 발생할 수 있다.

확인:

```bash
kubectl describe aigatewayroute envoy-ai-gateway-basic
```

대응:

curl 요청에 `x-ai-eg-model` 헤더를 포함한다.

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
