#!/usr/bin/env bash
set -euo pipefail

# Envoy AI Gateway v0.5에서 OpenRouter 실제 LLM backend 호출을 검증한다.
# 전제:
# - kind-aigw-v05 클러스터가 준비되어 있어야 한다.
# - openrouter-api-key Secret이 default namespace에 있어야 한다.
# - Secret에는 apiKey 키가 있어야 한다.

CLUSTER_CONTEXT="${CLUSTER_CONTEXT:-kind-aigw-v05}"
LOCAL_PORT="${LOCAL_PORT:-18086}"
MODEL="${OPENROUTER_MODEL:-google/gemini-2.0-flash-lite-001}"
SESSION_ID="${SESSION_ID:-openrouter-smoke-$(date +%s)}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${ROOT_DIR}/manifests/v05/openrouter-backend.yaml"

echo "[1/6] Kubernetes context 확인"
kubectl --context "${CLUSTER_CONTEXT}" config current-context

echo
echo "[2/6] OpenRouter Secret 확인"
if ! kubectl --context "${CLUSTER_CONTEXT}" get secret openrouter-api-key -n default >/dev/null 2>&1; then
  cat <<'EOF'
openrouter-api-key Secret이 없습니다.

다음 명령으로 먼저 생성하세요. API key는 레포에 커밋하지 않습니다.

export OPENROUTER_API_KEY='여기에_새_OpenRouter_Key'

kubectl create secret generic openrouter-api-key \
  -n default \
  --from-literal=apiKey="${OPENROUTER_API_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -
EOF
  exit 1
fi

echo
echo "[3/6] OpenRouter backend manifest 적용"
if [[ "${MODEL}" != "google/gemini-2.0-flash-lite-001" && "${MODEL}" != "openai/gpt-4o-mini" ]]; then
  echo "현재 manifest의 route match는 다음 모델만 포함합니다:"
  echo "- google/gemini-2.0-flash-lite-001"
  echo "- openai/gpt-4o-mini"
  echo "다른 모델을 쓰려면 manifests/v05/openrouter-backend.yaml의 AIGatewayRoute match를 먼저 추가하세요."
  exit 1
fi

kubectl --context "${CLUSTER_CONTEXT}" apply -f "${MANIFEST}"

echo
echo "[4/6] AIServiceBackend / BackendSecurityPolicy 상태 확인"
kubectl --context "${CLUSTER_CONTEXT}" get aiservicebackend openrouter -n default
kubectl --context "${CLUSTER_CONTEXT}" get backendsecuritypolicy openrouter-api-key -n default

echo
echo "[5/6] Envoy Service port-forward 시작"
ENVOY_SERVICE="$(kubectl --context "${CLUSTER_CONTEXT}" get svc -n envoy-gateway-system \
  --selector=gateway.envoyproxy.io/owning-gateway-namespace=default,gateway.envoyproxy.io/owning-gateway-name=envoy-ai-gateway-basic \
  -o jsonpath='{.items[0].metadata.name}')"

if [[ -z "${ENVOY_SERVICE}" ]]; then
  echo "Envoy Service를 찾지 못했습니다."
  exit 1
fi

echo "Envoy Service: ${ENVOY_SERVICE}"
PORT_FORWARD_LOG="$(mktemp)"
kubectl --context "${CLUSTER_CONTEXT}" port-forward -n envoy-gateway-system "svc/${ENVOY_SERVICE}" "${LOCAL_PORT}:80" >"${PORT_FORWARD_LOG}" 2>&1 &
PORT_FORWARD_PID="$!"
trap 'kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true; rm -f "${PORT_FORWARD_LOG}"' EXIT

sleep 3
if ! kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1; then
  echo "port-forward 시작에 실패했습니다."
  cat "${PORT_FORWARD_LOG}"
  exit 1
fi

echo
echo "[6/6] OpenRouter chat completions 호출"
RESPONSE_HEADERS="$(mktemp)"
RESPONSE_BODY="$(mktemp)"
trap 'kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true; rm -f "${PORT_FORWARD_LOG}" "${RESPONSE_HEADERS}" "${RESPONSE_BODY}"' EXIT

HTTP_STATUS="$(curl -sS \
  -D "${RESPONSE_HEADERS}" \
  -o "${RESPONSE_BODY}" \
  -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -H "x-ai-eg-model: ${MODEL}" \
  -H "x-session-id: ${SESSION_ID}" \
  -d "{
    \"model\": \"${MODEL}\",
    \"messages\": [
      {
        \"role\": \"user\",
        \"content\": \"한국어로 한 문장만 답해줘. Envoy AI Gateway를 통해 OpenRouter 호출이 되었는지 확인 중이야.\"
      }
    ],
    \"max_tokens\": 80
  }" \
  "http://localhost:${LOCAL_PORT}/v1/chat/completions")"

echo "HTTP status: ${HTTP_STATUS}"
echo "Model: ${MODEL}"
echo
echo "응답 body:"
cat "${RESPONSE_BODY}"
echo

if [[ "${HTTP_STATUS}" != "200" ]]; then
  echo
  echo "OpenRouter 호출이 실패했습니다. 응답 header:"
  cat "${RESPONSE_HEADERS}"
  exit 1
fi

if ! grep -q '"choices"' "${RESPONSE_BODY}"; then
  echo
  echo "HTTP 200이지만 OpenAI 호환 choices 필드가 없습니다."
  exit 1
fi

echo
echo "검증 완료: Envoy AI Gateway v0.5 -> OpenRouter 실제 LLM 호출 성공"
echo
echo "참고: OpenRouter route가 현재 클러스터에 적용된 상태로 남아 있습니다."
echo "테스트 backend로 되돌리려면 다음 명령을 실행하세요:"
echo "kubectl --context ${CLUSTER_CONTEXT} apply -f manifests/v05/basic-migrated.yaml"
