# AGENTS.md

## 레포 목적

이 레포는 Envoy AI Gateway v0.4 baseline 재현, v0.5 마이그레이션 계획 수립, session-based short-term memory PoC 설계와 검증 절차를 문서화하기 위한 작업 레포다.

서비스 애플리케이션 코드 레포가 아니라, Kubernetes, Envoy Gateway, Envoy AI Gateway, Redis, ExtProc 기반 PoC를 재현 가능하게 정리하는 것이 목적이다.

## 작성 언어

- 모든 문서는 한국어로 작성한다.
- Bash 스크립트 주석도 한국어로 작성한다.
- 명령어, 파일명, Kubernetes resource 이름, 변수명은 영어를 사용한다.

## 검증 상태 표기

문서에는 실제로 검증한 내용과 아직 검증하지 않은 계획/추정 내용을 명확히 구분한다.

- 실제 로컬 환경에서 실행해 성공한 내용에는 **검증 완료**를 표시한다.
- 아직 실행하지 않은 내용에는 **계획** 또는 **검토 필요**를 표시한다.
- v0.5와 Memory PoC는 구현 전 단계이므로 단정적으로 쓰지 않는다.

## Kubernetes / Helm 명령 규칙

- Kubernetes, Envoy Gateway, Envoy AI Gateway 버전을 명시한다.
- Helm chart 설치 명령에는 `--version`을 사용한다.
- Kind cluster 생성 시 검증된 Kubernetes node image를 명시한다.
- main 브랜치 raw URL을 사용하지 않는다.
- GitHub raw URL을 사용할 때는 반드시 버전 태그를 명시한다.

예:

```bash
kind create cluster --name aigw-v04 --image kindest/node:v1.32.0
```

```bash
helm upgrade -i eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.5.4 \
  --namespace envoy-gateway-system \
  --create-namespace
```

## 삭제 명령 규칙

- 위험한 삭제 명령은 자동으로 실행하지 않는다.
- `kind delete cluster`, namespace 삭제, Helm release 삭제 등은 사용자 확인 후 수행한다.
- 스크립트에서 삭제가 필요하면 확인 프롬프트를 둔다.

## 문서 구조 규칙

- 성공 경로와 Troubleshooting은 분리한다.
- 성공 경로는 각 버전별 baseline 또는 migration 문서에 작성한다.
- 실패 사례와 대응은 `docs/99-troubleshooting.md`에 작성한다.
- 새 명령을 추가할 때는 목적과 예상 결과를 함께 적는다.

## 스크립트 작성 규칙

- Bash script는 `set -euo pipefail`을 사용한다.
- 가능한 idempotent하게 작성한다.
- 이미 존재하는 cluster, repo, Helm release는 재사용한다.
- 위험한 삭제는 사용자 확인 없이 수행하지 않는다.
- main 브랜치 example을 내려받지 않는다.

## v0.4 baseline 기준

**검증 완료**

- Kubernetes v1.32.0
- Envoy Gateway v1.5.4
- Envoy AI Gateway v0.4.0
- v0.4.0 태그의 `examples/basic/basic.yaml`
- port-forward 기반 `/v1/chat/completions` HTTP 200 OK

## v0.5 / Memory 기준

**계획 / 검토 필요**

- v0.5 migration은 아직 직접 검증 전이다.
- GatewayConfig, `schema.prefix`, Body Mutation, Header Mutation은 실제 v0.5 클러스터에서 확인해야 한다.
- Memory PoC는 Redis와 `x-session-id` 기반 short-term memory를 우선 검토한다.
- MCP와 Agent Gateway는 이번 핵심 범위에서 제외한다.
