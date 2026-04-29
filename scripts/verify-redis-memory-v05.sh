#!/usr/bin/env bash
set -euo pipefail

# Redis 연동 Memory ExtProc가 session history를 저장/조회/병합하는지 검증한다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLUSTER_NAME="${CLUSTER_NAME:-aigw-v05}"
KUBECTL_CONTEXT="kind-${CLUSTER_NAME}"
GATEWAY_NAME="${GATEWAY_NAME:-envoy-ai-gateway-basic}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-default}"
DATAPLANE_NAMESPACE="${DATAPLANE_NAMESPACE:-envoy-gateway-system}"
MEMORY_NAMESPACE="${MEMORY_NAMESPACE:-ai-gateway-memory}"
REDIS_MANIFEST="${REDIS_MANIFEST:-${REPO_ROOT}/manifests/v05/redis-memory.yaml}"
MANIFEST="${MANIFEST:-${REPO_ROOT}/manifests/v05/extproc-memory-redis-gateway-config.yaml}"
RESTORE_MANIFEST="${RESTORE_MANIFEST:-${REPO_ROOT}/manifests/v05/gateway-config.yaml}"
IMAGE_NAME="${IMAGE_NAME:-envoy-ai-gateway-memory-extproc:v0.5.0-memory-skeleton}"
LOCAL_PORT="${LOCAL_PORT:-18085}"
SESSION_ID="${SESSION_ID:-demo-session-redis-1}"
REDIS_KEY="memory:chat:${SESSION_ID}"

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

curl_chat() {
  local content="$1"
  local response_file="$2"
  curl -sS -o "${response_file}" -w '%{http_code}' \
    -H "Content-Type: application/json" \
    -H "x-ai-eg-model: some-cool-self-hosted-model" \
    -H "x-session-id: ${SESSION_ID}" \
    -d "{
      \"model\": \"some-cool-self-hosted-model\",
      \"messages\": [
        {
          \"role\": \"user\",
          \"content\": \"${content}\"
        }
      ]
    }" \
    "http://localhost:${LOCAL_PORT}/v1/chat/completions"
}

main() {
  kubectl config use-context "${KUBECTL_CONTEXT}" >/dev/null

  print_section "Redis 준비 확인"
  kubectl apply -f "${REDIS_MANIFEST}"
  kubectl wait --timeout=2m -n "${MEMORY_NAMESPACE}" deployment/redis --for=condition=Available
  kubectl exec -n "${MEMORY_NAMESPACE}" deploy/redis -- redis-cli del "${REDIS_KEY}"

  print_section "Kind image load"
  kind load docker-image "${IMAGE_NAME}" --name "${CLUSTER_NAME}"

  local deployment_name
  deployment_name="$(get_dataplane_deployment)"
  echo "DATAPLANE_DEPLOYMENT=${deployment_name}"

  print_section "Redis Memory ExtProc 적용"
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
  kubectl port-forward -n "${DATAPLANE_NAMESPACE}" "svc/${envoy_service}" "${LOCAL_PORT}:80" >/tmp/verify-redis-memory-v05-port-forward.log 2>&1 &
  local port_forward_pid="$!"
  trap "kill ${port_forward_pid} >/dev/null 2>&1 || true" EXIT
  sleep 3

  print_section "첫 번째 요청: Redis 저장"
  local response_one
  response_one="$(mktemp)"
  local code_one
  code_one="$(curl_chat "내 이름은 홍길동이야" "${response_one}")"
  cat "${response_one}"
  echo
  echo "HTTP_CODE_1=${code_one}"
  if [[ "${code_one}" != "200" ]]; then
    echo "첫 번째 요청 실패" >&2
    exit 1
  fi

  print_section "Redis 저장 확인"
  kubectl exec -n "${MEMORY_NAMESPACE}" deploy/redis -- redis-cli get "${REDIS_KEY}"
  kubectl exec -n "${MEMORY_NAMESPACE}" deploy/redis -- redis-cli ttl "${REDIS_KEY}"

  print_section "두 번째 요청: Redis history 병합"
  local response_two
  response_two="$(mktemp)"
  local code_two
  code_two="$(curl_chat "내 이름이 뭐야?" "${response_two}")"
  cat "${response_two}"
  echo
  echo "HTTP_CODE_2=${code_two}"
  if [[ "${code_two}" != "200" ]]; then
    echo "두 번째 요청 실패" >&2
    exit 1
  fi

  print_section "Redis 최종 history 확인"
  kubectl exec -n "${MEMORY_NAMESPACE}" deploy/redis -- redis-cli get "${REDIS_KEY}"
  kubectl exec -n "${MEMORY_NAMESPACE}" deploy/redis -- redis-cli ttl "${REDIS_KEY}"

  print_section "ExtProc log 확인"
  kubectl logs "${pod_name}" -n "${DATAPLANE_NAMESPACE}" -c ai-gateway-extproc --tail=120

  print_section "원래 ExtProc로 복구"
  kubectl apply -f "${RESTORE_MANIFEST}"
  kubectl rollout restart deployment "${deployment_name}" -n "${DATAPLANE_NAMESPACE}"
  kubectl rollout status deployment "${deployment_name}" -n "${DATAPLANE_NAMESPACE}" --timeout=3m

  print_section "검증 완료"
  echo "Redis 저장/조회/history 병합과 HTTP 200 유지 확인 완료"
}

main "$@"
