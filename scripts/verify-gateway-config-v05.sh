#!/usr/bin/env bash
set -euo pipefail

# Envoy AI Gateway v0.5 GatewayConfig 반영 여부를 검증한다.
# 이 스크립트는 GatewayConfig를 적용하고 Gateway annotation으로 연결한다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLUSTER_NAME="${CLUSTER_NAME:-aigw-v05}"
KUBECTL_CONTEXT="kind-${CLUSTER_NAME}"
GATEWAY_NAME="${GATEWAY_NAME:-envoy-ai-gateway-basic}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-default}"
GATEWAY_CONFIG_NAME="${GATEWAY_CONFIG_NAME:-memory-poc-gateway-config}"
GATEWAY_CONFIG_MANIFEST="${GATEWAY_CONFIG_MANIFEST:-${REPO_ROOT}/manifests/v05/gateway-config.yaml}"
DATAPLANE_NAMESPACE="${DATAPLANE_NAMESPACE:-envoy-gateway-system}"
EXPECTED_MARKER_VALUE="${EXPECTED_MARKER_VALUE:-gateway-config-v05}"

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

get_running_dataplane_pod() {
  kubectl get pods -n "${DATAPLANE_NAMESPACE}" \
    -l "gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    --sort-by=.metadata.creationTimestamp \
    --no-headers \
    | awk '$3 == "Running" { pod_name=$1 } END { print pod_name }'
}

get_dataplane_deployment() {
  kubectl get deployment -n "${DATAPLANE_NAMESPACE}" \
    -l "gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    -o jsonpath='{.items[0].metadata.name}'
}

main() {
  require_command kubectl

  kubectl config use-context "${KUBECTL_CONTEXT}" >/dev/null

  if [[ ! -f "${GATEWAY_CONFIG_MANIFEST}" ]]; then
    echo "GatewayConfig manifest를 찾을 수 없습니다: ${GATEWAY_CONFIG_MANIFEST}" >&2
    exit 1
  fi

  print_section "적용 전 data plane 상태"
  kubectl get pods -n "${DATAPLANE_NAMESPACE}" \
    -l "gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    -o wide

  local before_pod
  before_pod="$(get_running_dataplane_pod)"
  echo "BEFORE_POD=${before_pod}"

  print_section "GatewayConfig 적용"
  kubectl apply -f "${GATEWAY_CONFIG_MANIFEST}"

  print_section "Gateway annotation 연결"
  kubectl annotate gateway "${GATEWAY_NAME}" \
    -n "${GATEWAY_NAMESPACE}" \
    "aigateway.envoyproxy.io/gateway-config=${GATEWAY_CONFIG_NAME}" \
    --overwrite

  print_section "GatewayConfig 상태"
  kubectl get gatewayconfig "${GATEWAY_CONFIG_NAME}" -n "${GATEWAY_NAMESPACE}" -o wide
  kubectl describe gatewayconfig "${GATEWAY_CONFIG_NAME}" -n "${GATEWAY_NAMESPACE}" || true

  print_section "data plane rollout 재시작"
  local dataplane_deployment
  dataplane_deployment="$(get_dataplane_deployment)"
  echo "DATAPLANE_DEPLOYMENT=${dataplane_deployment}"
  kubectl rollout restart deployment "${dataplane_deployment}" -n "${DATAPLANE_NAMESPACE}"
  kubectl rollout status deployment "${dataplane_deployment}" -n "${DATAPLANE_NAMESPACE}" --timeout=3m

  print_section "적용 후 data plane 상태"
  kubectl get pods -n "${DATAPLANE_NAMESPACE}" \
    -l "gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    -o wide

  local after_pod
  after_pod="$(get_running_dataplane_pod)"
  echo "AFTER_POD=${after_pod}"

  print_section "ai-gateway-extproc env 확인"
  local extproc_env
  extproc_env="$(kubectl get pod "${after_pod}" -n "${DATAPLANE_NAMESPACE}" \
    -o jsonpath='{range .spec.containers[?(@.name=="ai-gateway-extproc")].env[*]}{.name}={.value}{"\n"}{end}'
  )"
  echo "${extproc_env}"

  print_section "ai-gateway-extproc resources 확인"
  local extproc_resources
  extproc_resources="$(kubectl get pod "${after_pod}" -n "${DATAPLANE_NAMESPACE}" \
    -o jsonpath='{.spec.containers[?(@.name=="ai-gateway-extproc")].resources}{"\n"}'
  )"
  echo "${extproc_resources}"

  print_section "자동 검증"
  if ! grep -qx "MEMORY_POC_MARKER=${EXPECTED_MARKER_VALUE}" <<<"${extproc_env}"; then
    echo "MEMORY_POC_MARKER env가 기대값과 다릅니다." >&2
    exit 1
  fi

  if ! grep -q '"requests"' <<<"${extproc_resources}" || ! grep -q '"limits"' <<<"${extproc_resources}"; then
    echo "ai-gateway-extproc resources에 requests/limits가 없습니다." >&2
    exit 1
  fi

  echo "GatewayConfig env/resources 반영 확인 완료"

  print_section "검증 기준"
  cat <<'EOF'
성공 기준:
- GatewayConfig가 default namespace에 존재한다.
- Gateway metadata.annotations에 aigateway.envoyproxy.io/gateway-config 값이 있다.
- ai-gateway-extproc 컨테이너 env에 MEMORY_POC_MARKER=gateway-config-v05가 있다.
- ai-gateway-extproc 컨테이너 resources에 requests/limits가 있다.
EOF
}

main "$@"
