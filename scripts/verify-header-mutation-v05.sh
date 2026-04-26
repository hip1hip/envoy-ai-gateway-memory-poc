#!/usr/bin/env bash
set -euo pipefail

# Envoy AI Gateway v0.5 Header Mutation 동작을 검증한다.
# test upstream 로그에서 set/remove 헤더 반영 여부를 확인한다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLUSTER_NAME="${CLUSTER_NAME:-aigw-v05}"
KUBECTL_CONTEXT="kind-${CLUSTER_NAME}"
GATEWAY_NAME="${GATEWAY_NAME:-envoy-ai-gateway-basic}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-default}"
MANIFEST="${MANIFEST:-${REPO_ROOT}/manifests/v05/header-mutation-route.yaml}"
DATAPLANE_NAMESPACE="${DATAPLANE_NAMESPACE:-envoy-gateway-system}"
LOCAL_PORT="${LOCAL_PORT:-18083}"
BACKEND_DEPLOYMENT="${BACKEND_DEPLOYMENT:-envoy-ai-gateway-basic-testupstream}"

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "필수 명령을 찾을 수 없습니다: ${command_name}" >&2
    exit 1
  fi
}

print_section() {
  echo
  echo "== $1 =="
}

main() {
  require_command kubectl
  require_command curl

  kubectl config use-context "${KUBECTL_CONTEXT}" >/dev/null

  print_section "Header Mutation manifest 적용"
  kubectl apply -f "${MANIFEST}"

  print_section "AIGatewayRoute 상태 확인"
  kubectl get aigatewayroute "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" -o wide
  kubectl get aigatewayroute "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
    -o jsonpath='{.spec.rules[0].backendRefs[0].headerMutation}{"\n"}'

  local envoy_service
  envoy_service="$(kubectl get svc -n "${DATAPLANE_NAMESPACE}" \
    --selector="gateway.envoyproxy.io/owning-gateway-namespace=${GATEWAY_NAMESPACE},gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    -o jsonpath='{.items[0].metadata.name}')"
  echo "ENVOY_SERVICE=${envoy_service}"

  print_section "port-forward 시작"
  kubectl port-forward -n "${DATAPLANE_NAMESPACE}" "svc/${envoy_service}" "${LOCAL_PORT}:80" >/tmp/verify-header-mutation-v05-port-forward.log 2>&1 &
  local port_forward_pid="$!"
  trap "kill ${port_forward_pid} >/dev/null 2>&1 || true" EXIT
  sleep 3

  print_section "curl 검증"
  local http_code
  http_code="$(curl -sS -o /tmp/verify-header-mutation-v05-response.json -w '%{http_code}' \
    -H "Content-Type: application/json" \
    -H "x-ai-eg-model: some-cool-self-hosted-model" \
    -H "x-session-id: client-session" \
    -H "x-remove-me: should-not-reach-backend" \
    -d '{
      "model": "some-cool-self-hosted-model",
      "messages": [
        {
          "role": "system",
          "content": "Hi."
        }
      ]
    }' \
    "http://localhost:${LOCAL_PORT}/v1/chat/completions")"
  cat /tmp/verify-header-mutation-v05-response.json
  echo
  echo "HTTP_CODE=${http_code}"

  if [[ "${http_code}" != "200" ]]; then
    echo "Header Mutation 적용 후 curl 검증이 실패했습니다." >&2
    exit 1
  fi

  print_section "backend log 확인"
  local backend_logs
  backend_logs="$(kubectl logs "deployment/${BACKEND_DEPLOYMENT}" -n "${GATEWAY_NAMESPACE}" --tail=80)"
  echo "${backend_logs}"

  if ! grep -Fq 'header "X-Session-Id": [header-mutated-session]' <<<"${backend_logs}"; then
    echo "x-session-id set 결과가 backend log에서 확인되지 않았습니다." >&2
    exit 1
  fi

  if ! grep -Fq 'header "X-Memory-Policy": [short-term]' <<<"${backend_logs}"; then
    echo "x-memory-policy set 결과가 backend log에서 확인되지 않았습니다." >&2
    exit 1
  fi

  if grep -Fq 'X-Remove-Me' <<<"${backend_logs}"; then
    echo "x-remove-me remove 결과가 backend log에서 확인되지 않았습니다." >&2
    exit 1
  fi

  print_section "검증 완료"
  echo "Header Mutation set/remove가 backend 요청 헤더에 반영됐습니다."
}

main "$@"
