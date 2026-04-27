#!/usr/bin/env bash
set -euo pipefail

# Redis 없이 custom Memory ExtProc skeleton이 request body를 읽고 dummy message를 주입하는지 검증한다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLUSTER_NAME="${CLUSTER_NAME:-aigw-v05}"
KUBECTL_CONTEXT="kind-${CLUSTER_NAME}"
GATEWAY_NAME="${GATEWAY_NAME:-envoy-ai-gateway-basic}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-default}"
DATAPLANE_NAMESPACE="${DATAPLANE_NAMESPACE:-envoy-gateway-system}"
MANIFEST="${MANIFEST:-${REPO_ROOT}/manifests/v05/extproc-memory-skeleton-gateway-config.yaml}"
RESTORE_MANIFEST="${RESTORE_MANIFEST:-${REPO_ROOT}/manifests/v05/gateway-config.yaml}"
IMAGE_NAME="${IMAGE_NAME:-envoy-ai-gateway-memory-extproc:v0.5.0-memory-skeleton}"
LOCAL_PORT="${LOCAL_PORT:-18084}"

print_section() {
  echo
  echo "== $1 =="
}

get_dataplane_deployment() {
  kubectl get deployment -n "${DATAPLANE_NAMESPACE}" \
    -l "gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    -o jsonpath='{.items[0].metadata.name}'
}

get_running_dataplane_pod() {
  kubectl get pods -n "${DATAPLANE_NAMESPACE}" \
    -l "gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    --sort-by=.metadata.creationTimestamp \
    --no-headers \
    | awk '$3 == "Running" { pod_name=$1 } END { print pod_name }'
}

main() {
  kubectl config use-context "${KUBECTL_CONTEXT}" >/dev/null

  print_section "Kind image load"
  kind load docker-image "${IMAGE_NAME}" --name "${CLUSTER_NAME}"

  local deployment_name
  deployment_name="$(get_dataplane_deployment)"
  echo "DATAPLANE_DEPLOYMENT=${deployment_name}"

  print_section "custom Memory ExtProc 적용"
  kubectl apply -f "${MANIFEST}"
  kubectl annotate gateway "${GATEWAY_NAME}" \
    -n "${GATEWAY_NAMESPACE}" \
    "aigateway.envoyproxy.io/gateway-config=memory-poc-gateway-config" \
    --overwrite
  kubectl rollout restart deployment "${deployment_name}" -n "${DATAPLANE_NAMESPACE}"
  kubectl rollout status deployment "${deployment_name}" -n "${DATAPLANE_NAMESPACE}" --timeout=3m

  local pod_name
  pod_name="$(get_running_dataplane_pod)"
  echo "POD=${pod_name}"
  kubectl get pod "${pod_name}" -n "${DATAPLANE_NAMESPACE}" \
    -o jsonpath='{.spec.containers[?(@.name=="ai-gateway-extproc")].image}{"\n"}'

  print_section "port-forward 시작"
  local envoy_service
  envoy_service="$(kubectl get svc -n "${DATAPLANE_NAMESPACE}" \
    --selector="gateway.envoyproxy.io/owning-gateway-namespace=${GATEWAY_NAMESPACE},gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    -o jsonpath='{.items[0].metadata.name}')"
  kubectl port-forward -n "${DATAPLANE_NAMESPACE}" "svc/${envoy_service}" "${LOCAL_PORT}:80" >/tmp/verify-memory-extproc-skeleton-port-forward.log 2>&1 &
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
    -H "x-session-id: skeleton-session-1" \
    -d '{
      "model": "some-cool-self-hosted-model",
      "messages": [
        {
          "role": "user",
          "content": "Redis 전 dummy memory 주입 테스트"
        }
      ]
    }' \
    "http://localhost:${LOCAL_PORT}/v1/chat/completions")"

  cat "${response_headers}"
  cat "${response_body}"
  echo
  echo "HTTP_CODE=${http_code}"

  if [[ "${http_code}" != "200" ]]; then
    echo "custom Memory ExtProc skeleton 검증 요청이 실패했습니다." >&2
    exit 1
  fi

  print_section "ExtProc log 확인"
  kubectl logs "${pod_name}" -n "${DATAPLANE_NAMESPACE}" -c ai-gateway-extproc --tail=80

  print_section "test upstream log 확인"
  kubectl logs deployment/envoy-ai-gateway-basic-testupstream -n "${GATEWAY_NAMESPACE}" --tail=60

  print_section "원래 ExtProc로 복구"
  kubectl apply -f "${RESTORE_MANIFEST}"
  kubectl rollout restart deployment "${deployment_name}" -n "${DATAPLANE_NAMESPACE}"
  kubectl rollout status deployment "${deployment_name}" -n "${DATAPLANE_NAMESPACE}" --timeout=3m

  print_section "검증 완료"
  echo "custom Memory ExtProc skeleton 적용 상태에서 HTTP 200과 dummy memory injection log를 확인했습니다."
}

main "$@"
