#!/usr/bin/env bash
set -euo pipefail

# Envoy AI Gateway v0.5 schema.prefix 반영 여부를 검증한다.
# 기존 /v1/chat/completions 요청이 prefix 명시 후에도 HTTP 200을 반환하는지 확인한다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLUSTER_NAME="${CLUSTER_NAME:-aigw-v05}"
KUBECTL_CONTEXT="kind-${CLUSTER_NAME}"
GATEWAY_NAME="${GATEWAY_NAME:-envoy-ai-gateway-basic}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-default}"
MANIFEST="${MANIFEST:-${REPO_ROOT}/manifests/v05/schema-prefix-backend.yaml}"
DATAPLANE_NAMESPACE="${DATAPLANE_NAMESPACE:-envoy-gateway-system}"
LOCAL_PORT="${LOCAL_PORT:-18081}"

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

  print_section "schema.prefix manifest 적용"
  kubectl apply -f "${MANIFEST}"

  print_section "AIServiceBackend schema 확인"
  kubectl get aiservicebackend envoy-ai-gateway-basic-testupstream \
    -n "${GATEWAY_NAMESPACE}" \
    -o jsonpath='{.spec.schema}{"\n"}'

  print_section "AIServiceBackend 상태 확인"
  kubectl get aiservicebackend envoy-ai-gateway-basic-testupstream -n "${GATEWAY_NAMESPACE}" -o wide

  local envoy_service
  envoy_service="$(kubectl get svc -n "${DATAPLANE_NAMESPACE}" \
    --selector="gateway.envoyproxy.io/owning-gateway-namespace=${GATEWAY_NAMESPACE},gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    -o jsonpath='{.items[0].metadata.name}')"
  echo "ENVOY_SERVICE=${envoy_service}"

  print_section "port-forward 시작"
  kubectl port-forward -n "${DATAPLANE_NAMESPACE}" "svc/${envoy_service}" "${LOCAL_PORT}:80" >/tmp/verify-schema-prefix-v05-port-forward.log 2>&1 &
  local port_forward_pid="$!"
  trap "kill ${port_forward_pid} >/dev/null 2>&1 || true" EXIT
  sleep 3

  print_section "curl 검증"
  local http_code
  http_code="$(curl -sS -o /tmp/verify-schema-prefix-v05-response.json -w '%{http_code}' \
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

  cat /tmp/verify-schema-prefix-v05-response.json
  echo
  echo "HTTP_CODE=${http_code}"

  if [[ "${http_code}" != "200" ]]; then
    echo "schema.prefix 적용 후 curl 검증이 실패했습니다." >&2
    exit 1
  fi

  print_section "검증 완료"
  echo "schema.prefix=/v1 적용 후 /v1/chat/completions 요청이 HTTP 200을 반환했습니다."
}

main "$@"
