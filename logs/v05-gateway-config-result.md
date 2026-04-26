# v0.5 GatewayConfig 검증 결과

## 상태

**검증 완료**

2026-04-27 기준 로컬 WSL2 Ubuntu, Docker Desktop, Kind `aigw-v05` 환경에서 Envoy AI Gateway v0.5.0 `GatewayConfig`를 실제 Gateway에 연결해 ExtProc 컨테이너 설정 반영을 확인했다.

## 목적

Memory PoC에서 Redis URL, TTL, 최근 메시지 개수 같은 플랫폼 설정을 Gateway 단위로 ExtProc에 전달할 수 있는지 확인한다.

## 검증 환경

- Kubernetes: v1.32.0
- Kind cluster: `aigw-v05`
- Envoy Gateway: v1.6.0
- Envoy AI Gateway: v0.5.0
- Gateway: `default/envoy-ai-gateway-basic`
- GatewayConfig: `default/memory-poc-gateway-config`
- Data plane namespace: `envoy-gateway-system`

## 검증 manifest

```text
manifests/v05/gateway-config.yaml
```

주요 설정:

```text
MEMORY_POC_MARKER=gateway-config-v05
MEMORY_TTL_SECONDS=3600
MEMORY_MAX_HISTORY_MESSAGES=20
REDIS_URL=redis://redis.ai-gateway-memory.svc.cluster.local:6379
resources.requests.cpu=50m
resources.requests.memory=64Mi
resources.limits.cpu=250m
resources.limits.memory=256Mi
```

## 실행 명령

목적: GatewayConfig 적용, Gateway annotation 연결, data plane rollout 후 ExtProc 컨테이너 설정을 확인한다.

```bash
./scripts/verify-gateway-config-v05.sh
```

예상 결과:

- GatewayConfig가 `Accepted` 상태가 된다.
- Gateway annotation에 `aigateway.envoyproxy.io/gateway-config=memory-poc-gateway-config`가 생긴다.
- 새 data plane Pod의 `ai-gateway-extproc` 컨테이너 env/resources에 manifest 값이 반영된다.

## 관찰 결과

### 1. GatewayConfig 적용과 annotation 연결

**검증 완료**

```text
gatewayconfig.aigateway.envoyproxy.io/memory-poc-gateway-config unchanged
gateway.gateway.networking.k8s.io/envoy-ai-gateway-basic annotated
```

GatewayConfig 상태:

```text
NAME                        STATUS
memory-poc-gateway-config   Accepted
```

### 2. 기존 data plane Pod에는 즉시 반영되지 않음

**검증 완료**

처음 GatewayConfig를 적용하고 Gateway annotation을 연결했을 때 `GatewayConfig`는 `Accepted`였지만 기존 `ai-gateway-extproc` 컨테이너 env/resources는 비어 있었다.

```text
--- extproc env ---

--- extproc resources ---
{}
```

판단:

- GatewayConfig 자체는 정상 reconcile되었다.
- 그러나 이미 생성된 data plane Pod에는 env/resources가 즉시 in-place 반영되지 않았다.
- 로컬 검증에서는 새 data plane Pod 생성이 필요했다.

### 3. data plane rollout restart 후 반영 확인

**검증 완료**

```text
deployment "envoy-default-envoy-ai-gateway-basic-21a9f8f8" successfully rolled out
```

새 Pod의 `ai-gateway-extproc` env:

```text
MEMORY_POC_MARKER=gateway-config-v05
MEMORY_TTL_SECONDS=3600
MEMORY_MAX_HISTORY_MESSAGES=20
REDIS_URL=redis://redis.ai-gateway-memory.svc.cluster.local:6379
```

새 Pod의 `ai-gateway-extproc` resources:

```json
{"limits":{"cpu":"250m","memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}
```

## 결론

**검증 완료**

- v0.5 `GatewayConfig`는 Gateway annotation으로 연결할 수 있다.
- `spec.extProc.kubernetes.env`는 `ai-gateway-extproc` 컨테이너 env로 반영된다.
- `spec.extProc.kubernetes.resources`는 `ai-gateway-extproc` 컨테이너 resources로 반영된다.
- Memory PoC 설정값인 Redis URL, TTL, 최근 메시지 개수는 GatewayConfig env로 전달하는 전략을 사용할 수 있다.

## 주의점

**검증 완료**

- GatewayConfig가 `Accepted` 상태가 되어도 기존 data plane Pod에는 즉시 반영되지 않을 수 있다.
- 검증 환경에서는 data plane Deployment rollout restart 후 새 Pod에서 반영을 확인했다.
- 운영 환경에서는 GatewayConfig 변경 시 data plane 재생성 조건과 rollout 정책을 별도로 확인해야 한다.

## 관련 raw log

```text
logs/v05-gateway-config-verify-2026-04-27.log
logs/v05-gateway-config-rollout-2026-04-27.log
logs/v05-gateway-config-verify-rerun-2026-04-27.log
logs/v05-gateway-config-verify-final-2026-04-27.log
```
