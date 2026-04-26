# v0.5 Header Mutation 검증 결과

## 상태

**검증 완료**

2026-04-27 기준 Kind `aigw-v05` 환경에서 `AIGatewayRoute.spec.rules.backendRefs[].headerMutation`의 set/remove 동작을 확인했다.

## 검증 내용

적용 manifest:

```text
manifests/v05/header-mutation-route.yaml
```

설정:

```yaml
headerMutation:
  set:
    - name: x-session-id
      value: header-mutated-session
    - name: x-memory-policy
      value: short-term
  remove:
    - x-remove-me
```

실행 명령:

```bash
./scripts/verify-header-mutation-v05.sh
```

## 결과

```text
AIGatewayRoute Accepted
HTTP_CODE=200
header "X-Session-Id": [header-mutated-session]
header "X-Memory-Policy": [short-term]
```

`x-remove-me`는 backend log에서 확인되지 않았다.

## 결론

- route backendRef 위치의 Header Mutation set/remove는 backend 전달 요청 헤더에 반영된다.
- Memory PoC에서 `x-session-id` 전달, 내부 정책 헤더 주입, 불필요한 client header 제거에 사용할 수 있다.

## 주의점

- 검증 당시 이전 단계에서 적용한 Body Mutation 설정이 남아 있어 test upstream의 model은 `body-mutated-model`로 감지됐다.
- Header Mutation 검증 자체는 backend log의 header set/remove 기준으로 판단했다.

## 관련 raw log

```text
logs/v05-header-mutation-verify-2026-04-27.log
```
