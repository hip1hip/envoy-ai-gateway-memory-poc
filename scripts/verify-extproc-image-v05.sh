#!/usr/bin/env bash
set -euo pipefail

# Envoy AI Gateway v0.5에서 GatewayConfig로 ExtProc image 교체가 가능한지 검증한다.
# invalid image를 적용해 ImagePullBackOff를 확인한 뒤 원래 GatewayConfig로 복구한다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLUSTER_NAME="${CLUSTER_NAME:-aigw-v05}"
KUBECTL_CONTEXT="kind-${CLUSTER_NAME}"
GATEWAY_NAME="${GATEWAY_NAME:-envoy-ai-gateway-basic}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-default}"
DATAPLANE_NAMESPACE="${DATAPLANE_NAMESPACE:-envoy-gateway-system}"
INVALID_MANIFEST="${INVALID_MANIFEST:-${REPO_ROOT}/manifests/v05/extproc-image-override-invalid.yaml}"
RESTORE_MANIFEST="${RESTORE_MANIFEST:-${REPO_ROOT}/manifests/v05/gateway-config.yaml}"
INVALID_IMAGE="${INVALID_IMAGE:-registry.invalid/envoy-ai-gateway-memory-extproc:plan-a-check}"

print_section() {
  echo
  echo "== $1 =="
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "필수 명령을 찾을 수 없습니다: ${command_name}" >&2
    exit 1
  fi
}

get_dataplane_deployment() {
  kubectl get deployment -n "${DATAPLANE_NAMESPACE}" \
    -l "gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    -o jsonpath='{.items[0].metadata.name}'
}

get_extproc_image_from_deployment() {
  local deployment_name="$1"
  kubectl get deployment "${deployment_name}" -n "${DATAPLANE_NAMESPACE}" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="ai-gateway-extproc")].image}{"\n"}'
}

get_latest_dataplane_pod() {
  kubectl get pods -n "${DATAPLANE_NAMESPACE}" \
    -l "gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    --sort-by=.metadata.creationTimestamp \
    --no-headers \
    | tail -1 \
    | awk '{print $1}'
}

get_extproc_image_from_pod() {
  local pod_name="$1"
  kubectl get pod "${pod_name}" -n "${DATAPLANE_NAMESPACE}" \
    -o jsonpath='{.spec.containers[?(@.name=="ai-gateway-extproc")].image}{"\n"}'
}

main() {
  require_command kubectl
  kubectl config use-context "${KUBECTL_CONTEXT}" >/dev/null

  local deployment_name
  deployment_name="$(get_dataplane_deployment)"
  echo "DATAPLANE_DEPLOYMENT=${deployment_name}"

  print_section "현재 ExtProc image"
  local before_pod
  before_pod="$(get_latest_dataplane_pod)"
  echo "POD=${before_pod}"
  get_extproc_image_from_pod "${before_pod}"

  print_section "invalid image GatewayConfig 적용"
  kubectl apply -f "${INVALID_MANIFEST}"
  kubectl annotate gateway "${GATEWAY_NAME}" \
    -n "${GATEWAY_NAMESPACE}" \
    "aigateway.envoyproxy.io/gateway-config=memory-poc-gateway-config" \
    --overwrite

  kubectl rollout restart deployment "${deployment_name}" -n "${DATAPLANE_NAMESPACE}"
  set +e
  kubectl rollout status deployment "${deployment_name}" -n "${DATAPLANE_NAMESPACE}" --timeout=30s
  local rollout_status=$?
  set -e
  echo "EXPECTED_ROLLOUT_STATUS=${rollout_status}"

  print_section "invalid image 반영 확인"
  local invalid_pod
  invalid_pod="$(get_latest_dataplane_pod)"
  echo "POD=${invalid_pod}"
  local current_image
  current_image="$(get_extproc_image_from_pod "${invalid_pod}")"
  echo "CURRENT_EXTPROC_IMAGE=${current_image}"
  if [[ "${current_image}" != "${INVALID_IMAGE}" ]]; then
    echo "ExtProc image가 invalid image로 바뀌지 않았습니다." >&2
    local verify_result=1
  else
    local verify_result=0
  fi

  kubectl get pods -n "${DATAPLANE_NAMESPACE}" \
    -l "gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    -o wide

  print_section "원래 GatewayConfig로 복구"
  kubectl apply -f "${RESTORE_MANIFEST}"
  kubectl rollout restart deployment "${deployment_name}" -n "${DATAPLANE_NAMESPACE}"
  kubectl rollout status deployment "${deployment_name}" -n "${DATAPLANE_NAMESPACE}" --timeout=3m

  print_section "복구 후 상태"
  local restored_pod
  restored_pod="$(get_latest_dataplane_pod)"
  echo "POD=${restored_pod}"
  get_extproc_image_from_pod "${restored_pod}"
  kubectl get pods -n "${DATAPLANE_NAMESPACE}" \
    -l "gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    -o wide

  if [[ "${verify_result}" != "0" ]]; then
    exit "${verify_result}"
  fi

  print_section "검증 완료"
  echo "GatewayConfig로 ExtProc image override가 data plane Deployment에 반영됨을 확인했습니다."
}

main "$@"
