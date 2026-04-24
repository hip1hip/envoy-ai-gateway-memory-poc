# v0.5 Tag Research Log

## 상태

**검증 완료**

WSL Ubuntu에서 `envoyproxy/ai-gateway`의 `v0.5.0` tag를 clone하고, v0.4 basic manifest와 v0.5 basic manifest를 비교했다.

## 확인 명령

```bash
git clone --branch v0.5.0 https://github.com/envoyproxy/ai-gateway.git /home/hip1h/workspace/ai-gateway-v05
cd /home/hip1h/workspace/ai-gateway-v05
git rev-parse --short HEAD
git describe --tags --exact-match
```

결과:

```text
b40501fe
v0.5.0
```

## Helm chart 확인

```bash
helm show chart oci://docker.io/envoyproxy/ai-gateway-helm --version v0.5.0
helm show chart oci://docker.io/envoyproxy/ai-gateway-crds-helm --version v0.5.0
```

결과:

```text
ai-gateway-helm appVersion: v0.5.0
ai-gateway-helm chart version: v0.5.0
ai-gateway-crds-helm appVersion: v0.5.0
ai-gateway-crds-helm chart version: v0.5.0
```

## v0.4 / v0.5 basic manifest 비교

```bash
sha256sum \
  /home/hip1h/workspace/ai-gateway-v04/examples/basic/basic.yaml \
  /home/hip1h/workspace/ai-gateway-v05/examples/basic/basic.yaml
```

결과:

```text
051cc1b5b4f31ec0dd0f4e01005f0ef469dba77acae4460fa86dcf73c0f81182  /home/hip1h/workspace/ai-gateway-v04/examples/basic/basic.yaml
051cc1b5b4f31ec0dd0f4e01005f0ef469dba77acae4460fa86dcf73c0f81182  /home/hip1h/workspace/ai-gateway-v05/examples/basic/basic.yaml
```

판단:

- v0.4.0과 v0.5.0의 `examples/basic/basic.yaml`은 동일하다.
- basic example만 보면 manifest diff 기반 migration 변경점은 나오지 않을 수 있다.
- 그래도 v0.5 CRD/controller 위에서 실제 apply, status, curl 검증은 필요하다.

## v0.5 CRD에서 확인한 변경점

### GatewayConfig

**검증 완료**

- `GatewayConfig` CRD가 존재한다.
- apiVersion은 `aigateway.envoyproxy.io/v1alpha1`이다.
- Gateway annotation `aigateway.envoyproxy.io/gateway-config`로 참조한다.
- 실제 CRD schema는 `spec.extProc.kubernetes.env`와 `spec.extProc.kubernetes.resources` 구조를 가진다.

### schema.prefix

**검증 완료**

`AIServiceBackend.spec.schema`에 `prefix` 필드가 존재한다.

CRD description 기준:

- `prefix`는 OpenAI compatible API prefix를 표현한다.
- `version`은 AzureOpenAI API version 용도다.
- OpenAI에서 `version`을 prefix처럼 쓰는 동작은 backward compatibility이며 future release에서 제거될 예정이라고 설명되어 있다.

### Body Mutation

**검증 완료**

`AIServiceBackend`와 `AIGatewayRoute` backend reference schema에 `bodyMutation`이 존재한다.

확인된 제한:

- top-level field set/remove 지원
- `set` 최대 16개
- `remove` 최대 16개

### Header Mutation

**검증 완료**

`AIServiceBackend`와 `AIGatewayRoute` backend reference schema에 `headerMutation`이 존재한다.

## 검토 필요

- v0.5 tag의 `site/docs/compatibility.md`에는 `v0.5.x` 행이 명시되어 있지 않았다.
- chart는 v0.5.0이 존재하므로 실제 설치 검증으로 compatibility를 확인한다.
- v0.5 basic manifest가 동일하더라도 controller reconciliation 결과가 v0.4와 동일한지는 아직 미검증이다.
