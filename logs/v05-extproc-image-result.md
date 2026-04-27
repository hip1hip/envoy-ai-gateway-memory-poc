# v0.5 ExtProc image override 검증 결과

## 상태

**검증 완료**

2026-04-27 기준 Kind `aigw-v05` 환경에서 `GatewayConfig`로 `ai-gateway-extproc` sidecar image를 교체할 수 있음을 확인했다.

## 목적

Plan A인 ExtProc 기반 Memory 구현이 가능한지 보기 위한 첫 관문이다.

확인 질문:

- 우리가 만든 custom Memory ExtProc image를 Envoy AI Gateway data plane에 끼워 넣을 수 있는가?

## 검증 방법

의도적으로 존재하지 않는 image를 설정했다.

```text
registry.invalid/envoy-ai-gateway-memory-extproc:plan-a-check
```

적용 manifest:

```text
manifests/v05/extproc-image-override-invalid.yaml
```

실행 script:

```bash
./scripts/verify-extproc-image-v05.sh
```

## 결과

기존 image:

```text
docker.io/envoyproxy/ai-gateway-extproc:v0.5.0
```

invalid image 적용 후:

```text
CURRENT_EXTPROC_IMAGE=registry.invalid/envoy-ai-gateway-memory-extproc:plan-a-check
STATUS=ErrImagePull
```

복구 후:

```text
docker.io/envoyproxy/ai-gateway-extproc:v0.5.0
STATUS=Running
READY=3/3
```

## 결론

**검증 완료**

- `GatewayConfig.spec.extProc.kubernetes.image`로 `ai-gateway-extproc` sidecar image를 바꿀 수 있다.
- image 변경은 data plane Pod 생성 시 반영된다.
- 잘못된 image를 넣으면 새 Pod의 `ai-gateway-extproc`가 `ErrImagePull` 상태가 된다.
- 원래 `GatewayConfig`로 복구 후 data plane Pod가 다시 `3/3 Running`이 됐다.

## Plan A 판단

Plan A인 ExtProc 기반 Memory 구현은 다음 단계로 진행할 수 있다.

다음 검증:

- 최소 custom ExtProc skeleton image 작성
- Kind cluster에 image load
- `GatewayConfig`로 custom image 적용
- `/v1/chat/completions` HTTP 200 유지 확인

## 중간 이슈

첫 번째 script 실행에서는 `ai-gateway-extproc` image를 Deployment template에서 읽으려 했다.

실제 구조:

- Deployment template에는 `envoy`, `shutdown-manager`만 보인다.
- `ai-gateway-extproc`는 Pod 생성 시 sidecar로 주입된다.
- 따라서 image 확인은 Deployment가 아니라 Pod 기준으로 해야 한다.

이후 script를 Pod 기준으로 수정해 재검증했다.

## 관련 raw log

```text
logs/v05-extproc-image-verify-2026-04-27.log
logs/v05-extproc-image-verify-final-2026-04-27.log
```
