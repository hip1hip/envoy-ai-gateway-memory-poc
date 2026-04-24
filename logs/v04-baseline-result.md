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

## 2026-04-24 WSL clone 기반 스크립트 검증

### 상태

**검증 완료**

GitHub public repository를 WSL Ubuntu에서 새로 clone한 뒤 `setup-v04.sh`, `verify-v04.sh`, port-forward, curl 검증을 수행했다.

검증용 clone 경로:

```bash
/home/hip1h/workspace/envoy-ai-gateway-memory-poc-verify-20260424-152951
```

### 사전 상태

필수 도구 확인:

```bash
git
docker
kind
kubectl
helm
curl
```

Docker Desktop 연동 확인:

```bash
docker version
```

기존 Kind 클러스터:

```text
aigw-v04
```

기존 클러스터의 Kubernetes 버전:

```text
v1.32.0
```

### setup-v04.sh 실행 결과

처음 실행:

```bash
./scripts/setup-v04.sh
```

트러블:

```text
Permission denied
```

원인:

- GitHub에 올라간 초기 commit에서 `scripts/*.sh` 실행 비트가 설정되어 있지 않았다.

우회 실행:

```bash
bash scripts/setup-v04.sh
```

결과:

```text
== 사전 도구 확인 ==
== Kind 클러스터 확인 ==
기존 클러스터 'aigw-v04'를 재사용합니다. Kubernetes v1.32.0
== Envoy Gateway v1.5.4 설치 ==
Release "eg" has been upgraded.
deployment.apps/envoy-gateway condition met
== Envoy AI Gateway v0.4.0 설치 ==
Release "aieg-crd" has been upgraded.
Release "aieg" has been upgraded.
deployment.apps/ai-gateway-controller condition met
== v0.4 basic example 적용 ==
```

판단:

- `setup-v04.sh`는 기존 `aigw-v04` 클러스터를 정상 재사용했다.
- Helm release는 idempotent하게 upgrade 경로로 정상 처리됐다.
- basic example도 정상 적용됐다.
- 실행 비트 누락은 레포에서 수정 필요하다.

### verify-v04.sh 실행 결과

실행:

```bash
bash scripts/verify-v04.sh
```

주요 결과:

```text
aigw-v04-control-plane   Ready   control-plane   v1.32.0
envoy-gateway-...        1/1     Running
ai-gateway-controller-... 1/1     Running
envoy-ai-gateway-basic   PROGRAMMED=False
AIGatewayRoute           Accepted
AIServiceBackend         Accepted
ENVOY_SERVICE=envoy-default-envoy-ai-gateway-basic-21a9f8f8
```

판단:

- baseline 문서의 기대 상태와 일치한다.
- Kind 환경의 Gateway `PROGRAMMED=False`는 기존 판단대로 port-forward 검증으로 진행 가능했다.

### port-forward / curl 검증 결과

8080 port-forward 시도 중 확인된 상태:

```text
Unable to listen on port 8080
bind: address already in use
```

확인:

```bash
ps -ef | grep kubectl | grep port-forward
```

결과:

```text
kubectl port-forward -n envoy-gateway-system svc/envoy-default-envoy-ai-gateway-basic-21a9f8f8 8080:80
```

판단:

- 기존 `kubectl port-forward` 프로세스가 이미 같은 Envoy Service에 대해 8080을 사용 중이었다.
- 해당 연결을 재사용해서 curl 검증을 진행했다.

curl:

```bash
curl -sS -i \
  -H "Content-Type: application/json" \
  -H "x-ai-eg-model: some-cool-self-hosted-model" \
  --data @request-v04.json \
  http://localhost:8080/v1/chat/completions
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
        "content": "To infinity and beyond!"
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

### 검증 중 발생한 운영 트러블

1. `./scripts/setup-v04.sh` 직접 실행 시 `Permission denied`
   - 원인: Git 실행 비트 미설정
   - 조치: `bash scripts/setup-v04.sh`로 우회
   - 후속: `scripts/*.sh` 실행 비트 커밋 필요

2. PowerShell에서 WSL Bash로 multi-line 명령을 넘길 때 Bash 변수와 JSON quote가 깨짐
   - 예: `$VERIFY_DIR`, JSON body quote
   - 원인: PowerShell이 일부 문자를 먼저 해석
   - 조치: 단순 명령은 `wsl --cd ... -- <command>` 형태로 실행하고, JSON body는 파일로 분리

3. 8080 port-forward 충돌
   - 원인: 기존 `kubectl port-forward ... 8080:80` 프로세스가 실행 중
   - 조치: 기존 연결이 같은 Envoy Service임을 확인하고 curl 검증에 재사용

### 최종 판단

**검증 완료**

- GitHub public repository clone 성공
- `setup-v04.sh` 로직 성공
- `verify-v04.sh` 로직 성공
- Envoy Service port-forward 경로 확인
- `/v1/chat/completions` HTTP 200 OK 확인

단, 초기 공개 commit 기준으로 `scripts/*.sh` 실행 비트 누락이 있었으므로 후속 commit에서 수정한다.
