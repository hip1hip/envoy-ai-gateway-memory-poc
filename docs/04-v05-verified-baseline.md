# v0.5 Verified Baseline

## 한 줄 결론

**검증 완료**: Envoy AI Gateway basic scenario 기준 v0.4에서 v0.5로의 migration은 manifest 수정이 필요 없는 no-op migration이다.

## 검증한 것

- `aigw-v05` Kind 클러스터 생성
- Kubernetes v1.32.0 사용
- Envoy Gateway v1.6.0 설치
- Envoy AI Gateway v0.5.0 CRD / Controller 설치
- v0.4 source manifest 적용
- v0.5 migrated manifest 적용
- `AIGatewayRoute` Accepted 확인
- `AIServiceBackend` Accepted 확인
- Envoy data plane Pod Running 확인
- `/v1/chat/completions` curl HTTP 200 OK 확인

## Manifest 판단

v0.4.0과 v0.5.0의 `examples/basic/basic.yaml`은 동일하다.

```text
v0.4 basic sha256: 051cc1b5b4f31ec0dd0f4e01005f0ef469dba77acae4460fa86dcf73c0f81182
v0.5 basic sha256: 051cc1b5b4f31ec0dd0f4e01005f0ef469dba77acae4460fa86dcf73c0f81182
```

따라서 basic scenario의 migrated manifest도 동일 파일로 고정했다.

```text
manifests/v04/basic.yaml
manifests/v05/basic-upstream.yaml
manifests/v05/basic-migrated.yaml
```

## 왜 이것도 migration 검증인가

파일이 같더라도 다음을 실제로 확인해야 migration 성공이라고 볼 수 있다.

- v0.5 CRD가 v0.4 manifest를 받아주는지
- v0.5 controller가 route/backend를 정상 reconciliation 하는지
- Gateway Listener 조건이 정상인지
- Envoy data plane이 생성되는지
- 실제 client 요청이 HTTP 200으로 응답하는지

이번 검증에서는 위 항목을 모두 확인했다.

## 아직 남은 일

basic migration은 완료됐지만, v0.5 신규 기능 검증은 남아 있다.

1. `GatewayConfig` 검증
2. `schema.prefix` 검증
3. Body Mutation 검증
4. Header Mutation 검증
5. Memory PoC 설계 확정

## 용어

- **no-op migration**: 변경 없는 마이그레이션. 설정 파일을 수정하지 않아도 새 버전에서 그대로 동작하는 경우.
- **manifest**: Kubernetes 리소스를 정의하는 YAML 파일.
- **reconciliation**: Controller가 선언된 설정과 실제 실행 상태를 맞추는 과정.
- **data plane**: 실제 요청 트래픽을 처리하는 Envoy proxy Pod.
