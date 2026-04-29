#!/usr/bin/env bash
set -euo pipefail

# OpenRouter 실제 LLM backend와 Redis Memory ExtProc를 함께 검증한다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLUSTER_NAME="${CLUSTER_NAME:-aigw-v05}"
KUBECTL_CONTEXT="kind-${CLUSTER_NAME}"
GATEWAY_NAME="${GATEWAY_NAME:-envoy-ai-gateway-basic}"
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-default}"
DATAPLANE_NAMESPACE="${DATAPLANE_NAMESPACE:-envoy-gateway-system}"
MEMORY_NAMESPACE="${MEMORY_NAMESPACE:-ai-gateway-memory}"
LOCAL_PORT="${LOCAL_PORT:-18087}"
MODEL="${OPENROUTER_MODEL:-google/gemini-2.0-flash-lite-001}"
SESSION_ID="${SESSION_ID:-demo-openrouter-memory-1}"
REDIS_KEY="memory:chat:${SESSION_ID}"
IMAGE_NAME="${IMAGE_NAME:-envoy-ai-gateway-memory-extproc:v0.5.0-memory-skeleton}"

REDIS_MANIFEST="${REPO_ROOT}/manifests/v05/redis-memory.yaml"
OPENROUTER_MANIFEST="${REPO_ROOT}/manifests/v05/openrouter-backend.yaml"
MEMORY_GATEWAY_CONFIG="${REPO_ROOT}/manifests/v05/extproc-memory-redis-gateway-config.yaml"

print_section() {
  echo
  echo "== $1 =="
}

get_dataplane_deployment() {
  kubectl --context "${KUBECTL_CONTEXT}" get deployment -n "${DATAPLANE_NAMESPACE}" \
    -l "gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    -o jsonpath='{.items[0].metadata.name}'
}

get_running_dataplane_pod() {
  kubectl --context "${KUBECTL_CONTEXT}" get pods -n "${DATAPLANE_NAMESPACE}" \
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
    -H "x-ai-eg-model: ${MODEL}" \
    -H "x-session-id: ${SESSION_ID}" \
    -d "{
      \"model\": \"${MODEL}\",
      \"messages\": [
        {
          \"role\": \"user\",
          \"content\": \"${content}\"
        }
      ],
      \"max_tokens\": 120
    }" \
    "http://localhost:${LOCAL_PORT}/v1/chat/completions"
}

main() {
  print_section "전제 조건 확인"
  kubectl --context "${KUBECTL_CONTEXT}" get secret openrouter-api-key -n default >/dev/null
  docker image inspect "${IMAGE_NAME}" >/dev/null

  if [[ "${MODEL}" != "google/gemini-2.0-flash-lite-001" && "${MODEL}" != "openai/gpt-4o-mini" ]]; then
    echo "현재 route match는 ${MODEL}을 포함하지 않습니다. openrouter-backend.yaml에 모델을 먼저 추가하세요."
    exit 1
  fi

  print_section "Redis / OpenRouter / Memory ExtProc 적용"
  kubectl --context "${KUBECTL_CONTEXT}" apply -f "${REDIS_MANIFEST}"
  kubectl --context "${KUBECTL_CONTEXT}" wait --timeout=2m -n "${MEMORY_NAMESPACE}" deployment/redis --for=condition=Available
  kubectl --context "${KUBECTL_CONTEXT}" exec -n "${MEMORY_NAMESPACE}" deploy/redis -- redis-cli del "${REDIS_KEY}"
  kubectl --context "${KUBECTL_CONTEXT}" apply -f "${OPENROUTER_MANIFEST}"
  kubectl --context "${KUBECTL_CONTEXT}" apply -f "${MEMORY_GATEWAY_CONFIG}"

  print_section "Memory ExtProc image 반영"
  kind load docker-image "${IMAGE_NAME}" --name "${CLUSTER_NAME}"
  local deployment_name
  deployment_name="$(get_dataplane_deployment)"
  kubectl --context "${KUBECTL_CONTEXT}" annotate gateway "${GATEWAY_NAME}" \
    -n "${GATEWAY_NAMESPACE}" \
    "aigateway.envoyproxy.io/gateway-config=memory-poc-gateway-config" \
    --overwrite
  kubectl --context "${KUBECTL_CONTEXT}" rollout restart deployment "${deployment_name}" -n "${DATAPLANE_NAMESPACE}"
  kubectl --context "${KUBECTL_CONTEXT}" rollout status deployment "${deployment_name}" -n "${DATAPLANE_NAMESPACE}" --timeout=3m

  local pod_name
  pod_name="$(get_running_dataplane_pod)"
  echo "POD=${pod_name}"
  kubectl --context "${KUBECTL_CONTEXT}" get pod "${pod_name}" -n "${DATAPLANE_NAMESPACE}" \
    -o jsonpath='{.spec.containers[?(@.name=="ai-gateway-extproc")].image}{"\n"}'

  print_section "port-forward 시작"
  local envoy_service
  envoy_service="$(kubectl --context "${KUBECTL_CONTEXT}" get svc -n "${DATAPLANE_NAMESPACE}" \
    --selector="gateway.envoyproxy.io/owning-gateway-namespace=${GATEWAY_NAMESPACE},gateway.envoyproxy.io/owning-gateway-name=${GATEWAY_NAME}" \
    -o jsonpath='{.items[0].metadata.name}')"
  kubectl --context "${KUBECTL_CONTEXT}" port-forward -n "${DATAPLANE_NAMESPACE}" "svc/${envoy_service}" "${LOCAL_PORT}:80" >/tmp/verify-openrouter-memory-v05-port-forward.log 2>&1 &
  local port_forward_pid="$!"
  trap "kill ${port_forward_pid} >/dev/null 2>&1 || true" EXIT
  sleep 3

  print_section "첫 번째 요청: 이름 저장"
  local response_one
  response_one="$(mktemp)"
  local code_one
  code_one="$(curl_chat "내 이름은 홍길동입니다. 이 사실을 기억해줘." "${response_one}")"
  cat "${response_one}"
  echo
  echo "HTTP_CODE_1=${code_one}"
  [[ "${code_one}" == "200" ]]

  print_section "두 번째 요청: 이름 회상"
  local response_two
  response_two="$(mktemp)"
  local code_two
  code_two="$(curl_chat "내 이름이 뭐야? 이름만 짧게 답해줘." "${response_two}")"
  cat "${response_two}"
  echo
  echo "HTTP_CODE_2=${code_two}"
  [[ "${code_two}" == "200" ]]
  grep -q "홍길동" "${response_two}"

  print_section "Redis 저장 확인"
  kubectl --context "${KUBECTL_CONTEXT}" exec -n "${MEMORY_NAMESPACE}" deploy/redis -- redis-cli get "${REDIS_KEY}"
  kubectl --context "${KUBECTL_CONTEXT}" exec -n "${MEMORY_NAMESPACE}" deploy/redis -- redis-cli ttl "${REDIS_KEY}"

  print_section "검증 완료"
  echo "OpenRouter 실제 LLM이 Redis short-term memory 내용을 반영해 홍길동을 응답했다."
  echo "현재 클러스터에는 OpenRouter route와 Memory ExtProc가 적용된 상태로 남아 있다."
}

main "$@"
