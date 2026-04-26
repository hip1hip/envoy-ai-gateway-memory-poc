# Envoy AI Gateway v0.4 to v0.5 Memory PoC

이 레포는 서비스 코드 레포가 아니라, Envoy AI Gateway v0.4 baseline 재현, v0.5 마이그레이션 검토, session-based short-term memory PoC 설계를 문서화하고 자동화하기 위한 작업 레포입니다.

## 프로젝트 목적

- **검증 완료**: Envoy AI Gateway v0.4 baseline을 로컬 Kubernetes 환경에서 재현한다.
- **계획**: v0.5로 마이그레이션하면서 변경점을 문서화한다.
- **계획**: `x-session-id` 기반 short-term memory PoC를 구현한다.
- **설계 원칙**: Memory는 특정 앱 전용 기능이 아니라 플랫폼 레벨의 범용 Inference API 기능으로 제공되는 구조를 지향한다.
- **제외 범위**: MCP와 Agent Gateway 확장은 이번 핵심 범위에서 제외한다.

## 전체 진행 흐름

1. **v0.4 baseline 재현**
   - Kind Kubernetes v1.32.0 클러스터 생성
   - Envoy Gateway v1.5.4 설치
   - Envoy AI Gateway v0.4.0 설치
   - v0.4.0 태그의 `examples/basic/basic.yaml` 적용
   - `/v1/chat/completions` 요청으로 HTTP 200 확인

2. **v0.5 migration 검토**
   - v0.5 설치 방식과 의존성 확인
   - v0.4 manifest를 v0.5 환경에 그대로 적용해 migration 검증
   - basic scenario 기준 no-op migration 확인
   - `GatewayConfig`의 ExtProc env/resources 반영 확인
   - `schema.prefix`, Body Mutation, Header Mutation은 후속 기능 검증으로 분리

3. **Memory PoC 설계 및 구현**
   - Redis 기반 session memory 저장소 구성
   - `x-session-id` 헤더 기반 세션 분리
   - 최근 N개 메시지 sliding window 유지
   - TTL 기반 세션 만료
   - ExtProc 또는 Body Mutation 기반 구현 방안 검토

## 현재 상태

### v0.4 baseline

**검증 완료**

- Windows + WSL2 Ubuntu + Docker Desktop 연동
- Kind 클러스터 생성
- Kubernetes v1.32.0 노드 Ready
- Envoy Gateway v1.5.4 Pod Running
- Envoy AI Gateway v0.4.0 Controller Pod Running
- v0.4.0 태그의 basic example 적용
- AIGatewayRoute Accepted
- AIServiceBackend Accepted
- Envoy data plane Pod Running
- port-forward 기반 `/v1/chat/completions` HTTP 200 OK 확인

### v0.5 migration

**검증 완료**

- 별도 Kind 클러스터 `aigw-v05` 생성
- Kubernetes v1.32.0 노드 Ready
- Envoy Gateway v1.6.0 설치
- Envoy AI Gateway v0.5.0 CRD / Controller 설치
- v0.4 basic source manifest를 v0.5 환경에 적용
- AIGatewayRoute Accepted
- AIServiceBackend Accepted
- port-forward 기반 `/v1/chat/completions` HTTP 200 OK 확인
- basic scenario 기준 v0.4 to v0.5 manifest migration은 no-op으로 확인
- `GatewayConfig` 기반 ExtProc env/resources 반영 확인

**검토 필요**

- `schema.prefix` 기반 provider/backend manifest 작성 및 검증
- Body Mutation / Header Mutation 동작 검증

### Memory PoC

**계획 / 검토 필요**

- Redis 배포 방식 결정
- ExtProc 기반 Memory Service 구현 가능성 검토
- 요청 본문에 대화 히스토리 주입 방식 검증
- LLM/Test Backend 응답을 Redis에 저장하는 흐름 검증
- Redis 장애 시 fail-fast 또는 graceful degradation 정책 결정

## 문서 목록

- [프로젝트 컨텍스트](docs/00-project-context.md)
- [v0.4 baseline 재현 문서](docs/01-v04-baseline.md)
- [v0.5 migration 계획](docs/02-v05-migration-plan.md)
- [Memory PoC 설계 초안](docs/03-memory-poc-design.md)
- [v0.5 검증 완료 baseline](docs/04-v05-verified-baseline.md)
- [Troubleshooting](docs/99-troubleshooting.md)
- [v0.4 baseline 결과 로그](logs/v04-baseline-result.md)
- [v0.5 migration 결과 로그](logs/v05-migration-result.md)
- [v0.5 GatewayConfig 검증 결과](logs/v05-gateway-config-result.md)

## 빠른 시작 가이드

WSL2 Ubuntu에서 실행하는 것을 기준으로 합니다.

### 1. v0.4 baseline 설치

```bash
chmod +x scripts/setup-v04.sh
./scripts/setup-v04.sh
```

예상 결과:

- `kind-aigw-v04` context가 생성된다.
- `envoy-gateway-system` 네임스페이스에 Envoy Gateway가 설치된다.
- `envoy-ai-gateway-system` 네임스페이스에 AI Gateway Controller가 설치된다.
- default 네임스페이스에 v0.4 basic example 리소스가 생성된다.

### 2. 상태 확인

```bash
chmod +x scripts/verify-v04.sh
./scripts/verify-v04.sh
```

### 3. 별도 터미널에서 port-forward 실행

`verify-v04.sh`가 출력하는 `kubectl port-forward` 명령을 별도 터미널에서 실행합니다.

예시:

```bash
kubectl port-forward -n envoy-gateway-system svc/<ENVOY_SERVICE_NAME> 8080:80
```

### 4. curl 테스트

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

성공 기준:

- HTTP status가 `200 OK`이다.
- 응답 헤더에 `x-model: some-cool-self-hosted-model`가 포함된다.
- 응답 body에 assistant message가 포함된다.

### 5. v0.4 클러스터 정리

```bash
chmod +x scripts/cleanup-v04.sh
./scripts/cleanup-v04.sh
```

이 스크립트는 삭제 전 사용자 확인을 받습니다.
