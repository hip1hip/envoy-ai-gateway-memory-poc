#!/usr/bin/env bash
set -euo pipefail

# Envoy AI Gateway v0.5 Body Mutation 동작을 검증한다.
# 요청 body의 top-level model field가 backend 전달 전에 바뀌는지 확인한다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLUSTER_NAME="${CLUSTER_NAME:-aigw-v05}"
KUBECTL_CONTEXT="kind-${CLUSTER_NAME}"
GATEWAY_NAME="${GATEWAY_NAME:-envoy-ai-gateway-basic}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-default}"
ROUTE_MANIFEST="${ROUTE_MANIFEST:-${REPO_ROOT}/manifests/v05/body-mutation-route.yaml}"
BACKEND_MANIFEST="${BACKEND_MANIFEST:-${REPO_ROOT}/manifests/v05/body-mutation-backend.yaml}"
DATAPLANE_NAMESPACE="${DATAPLANE_NAMESPACE:-envoy-gateway-system}"
LOCAL_PORT="${LOCAL_PORT:-18082}"
EXPECTED_MODEL="${EXPECTED_MODEL:-body-mutated-model}"

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

  print_section "Body Mutation manifest 적용"
  kubectl apply -f "${ROUTE_MANIFEST}"
  kubectl apply -f "${BACKEND_MANIFEST}"

  print_section "AIGatewayRoute 상태 확인"
  kubectl get aigatewayroute "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" -o wide
  kubectl get aigatewayroute "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
    -o jsonpath='{.spec.rules[0].backendRefs[0].bodyMutation}{"\n"}'
  kubectl get aiservicebackend envoy-ai-gateway-basic-testupstream -n "${GATEWAY_NAMESPACE}" \
    -o jsonpath='{.spec.bodyMutation}{"\n"}'

  local envoy_service
  envoy_service="$(kubectl get svc -n "${DATAPLANE_NAMESPACE}" \
    --selector="gateway.envoyproxy.io/owning-gateway-namespace=${GATEWAY_NAMESPACE},gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    -o jsonpath='{.items[0].metadata.name}')"
  echo "ENVOY_SERVICE=${envoy_service}"

  print_section "port-forward 시작"
  kubectl port-forward -n "${DATAPLANE_NAMESPACE}" "svc/${envoy_service}" "${LOCAL_PORT}:80" >/tmp/verify-body-mutation-v05-port-forward.log 2>&1 &
  local port_forward_pid="$!"
  trap "kill ${port_forward_pid} >/dev/null 2>&1 || true" EXIT
  sleep 3

  print_section "curl 검증"
  local response_headers
  response_headers="$(mktemp)"
  local response_body
  response_body="$(mktemp)"

  local http_code
  http_code="$(curl -sS -D "${response_headers}" -o "${response_body}" -w '%{http_code}' \
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
    "http://localhost:${LOCAL_PORT}/v1/chat/completions")"

  cat "${response_headers}"
  cat "${response_body}"
  echo
  echo "HTTP_CODE=${http_code}"

  if [[ "${http_code}" != "200" ]]; then
    echo "Body Mutation 적용 후 curl 검증이 실패했습니다." >&2
    exit 1
  fi

  if ! grep -qi "^x-model: ${EXPECTED_MODEL}" "${response_headers}"; then
    echo "응답 x-model 헤더가 기대값과 다릅니다: ${EXPECTED_MODEL}" >&2
    exit 1
  fi

  print_section "검증 완료"
  echo "Body Mutation으로 request body model field가 ${EXPECTED_MODEL}(으)로 변경됐습니다."
}

main "$@"
