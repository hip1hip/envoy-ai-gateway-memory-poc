# v0.5 schema.prefix 검증 결과

## 상태

**검증 완료**

2026-04-27 기준 Kind `aigw-v05` 환경에서 `AIServiceBackend.spec.schema.prefix`를 실제 적용하고 `/v1/chat/completions` 요청이 유지되는지 확인했다.

## 검증 내용

적용 manifest:

```text
manifests/v05/schema-prefix-backend.yaml
```

핵심 설정:

```yaml
schema:
  name: OpenAI
  prefix: /v1
```

실행 명령:

```bash
./scripts/verify-schema-prefix-v05.sh
```

## 결과

```text
{"name":"OpenAI","prefix":"/v1"}
envoy-ai-gateway-basic-testupstream   Accepted
HTTP_CODE=200
```

결론:

- `schema.prefix=/v1` 적용 후에도 기존 client path `/v1/chat/completions`는 변경하지 않아도 된다.
- `AIServiceBackend`는 `Accepted` 상태를 유지했다.
- curl 검증은 HTTP 200 OK를 반환했다.

## 중간 이슈

첫 실행에서 HTTP 200 검증은 성공했지만, script 종료 시 `trap`에서 `port_forward_pid: unbound variable` 메시지가 발생했다.

원인:

- `port_forward_pid`를 function local 변수로 선언하고 `EXIT` trap에서 참조했다.

조치:

- trap 등록 시 PID 값을 문자열에 고정하도록 수정했다.
- 수정 후 재실행 결과 같은 검증이 에러 없이 완료됐다.

## 관련 raw log

```text
logs/v05-schema-prefix-verify-2026-04-27.log
logs/v05-schema-prefix-verify-final-2026-04-27.log
```
