# v0.5 Body Mutation 검증 결과

## 상태

**검증 완료**

2026-04-27 기준 Kind `aigw-v05` 환경에서 Body Mutation이 request body의 top-level field를 변경하는지 확인했다.

## 검증 내용

목표:

- 요청 body의 `model` 값을 `some-cool-self-hosted-model`에서 `body-mutated-model`로 변경한다.
- test upstream 응답 헤더 `x-model`이 `body-mutated-model`로 바뀌는지 확인한다.

## Route backendRef 위치 검증

**검토 필요**

적용 manifest:

```text
manifests/v05/body-mutation-route.yaml
```

결과:

```text
AIGatewayRoute Accepted
bodyMutation={"set":[{"path":"model","value":"\"body-mutated-model\""}]}
HTTP_CODE=200
x-model: some-cool-self-hosted-model
```

판단:

- `AIGatewayRoute.spec.rules.backendRefs[].bodyMutation`는 CRD에 존재하고 리소스도 `Accepted` 상태가 됐다.
- 그러나 이번 관측 기준에서는 backend 응답의 `x-model`이 원래 값으로 유지됐다.
- 따라서 route backendRef 위치의 Body Mutation 동작은 추가 확인이 필요하다.

## AIServiceBackend 위치 검증

**검증 완료**

적용 manifest:

```text
manifests/v05/body-mutation-backend.yaml
```

결과:

```text
AIServiceBackend Accepted
bodyMutation={"set":[{"path":"model","value":"\"body-mutated-model\""}]}
HTTP_CODE=200
x-model: body-mutated-model
```

결론:

- `AIServiceBackend.spec.bodyMutation.set`은 request body의 top-level `model` field를 변경했다.
- OpenAI compatible `/v1/chat/completions` 요청에서 Body Mutation이 실제 backend 전달 전에 적용됨을 확인했다.
- CRD 설명 기준으로 Body Mutation은 top-level field만 지원한다.

## Memory PoC 관점

**검토 필요**

- Body Mutation만으로 `messages[*]` 내부를 세밀하게 조작하는 것은 적합하지 않다.
- `messages` 배열 전체를 top-level field로 교체하는 방식은 가능성 검토가 필요하다.
- session memory 병합처럼 Redis 조회와 JSON merge가 필요한 기능은 ExtProc 또는 별도 Memory Service가 더 적합하다.

## 관련 raw log

```text
logs/v05-body-mutation-verify-2026-04-27.log
logs/v05-body-mutation-verify-backend-2026-04-27.log
```
