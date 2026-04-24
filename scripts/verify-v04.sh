#!/usr/bin/env bash
set -euo pipefail

# Envoy AI Gateway v0.4 baseline 상태를 확인하고 수동 검증 명령을 출력한다.

CLUSTER_NAME="${CLUSTER_NAME:-aigw-v04}"
KUBECTL_CONTEXT="kind-${CLUSTER_NAME}"

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

  kubectl config use-context "${KUBECTL_CONTEXT}" >/dev/null

  print_section "Kubernetes node 상태"
  kubectl get nodes -o wide

  print_section "Envoy Gateway Pod 상태"
  kubectl get pods -n envoy-gateway-system

  print_section "AI Gateway Controller Pod 상태"
  kubectl get pods -n envoy-ai-gateway-system

  print_section "Gateway 상태"
  kubectl get gateway

  print_section "Gateway describe 확인 안내"
  cat <<'EOF'
다음 명령으로 Listener 조건을 확인하세요.
확인할 주요 조건: Accepted=True, ResolvedRefs=True, Programmed=True

kubectl describe gateway envoy-ai-gateway-basic
EOF

  print_section "AIGatewayRoute 상태"
  kubectl get aigatewayroute

  print_section "AIGatewayRoute describe 확인 명령"
  echo "kubectl describe aigatewayroute envoy-ai-gateway-basic"

  print_section "AIServiceBackend 상태"
  kubectl get aiservicebackend

  print_section "AIServiceBackend describe 확인 명령"
  echo "kubectl describe aiservicebackend envoy-ai-gateway-basic-testupstream"

  print_section "Envoy Service 이름 추출"
  local envoy_service
  envoy_service="$(kubectl get svc -n envoy-gateway-system \
    --selector=gateway.envoyproxy.io/owning-gateway-namespace=default,gateway.envoyproxy.io/owning-gateway-name=envoy-ai-gateway-basic \
    -o jsonpath='{.items[0].metadata.name}')"

  if [[ -z "${envoy_service}" ]]; then
    echo "Envoy Service를 찾지 못했습니다. basic example 적용 상태를 확인하세요." >&2
    exit 1
  fi

  echo "ENVOY_SERVICE=${envoy_service}"

  print_section "별도 터미널에서 port-forward 실행"
  cat <<EOF
kubectl port-forward -n envoy-gateway-system svc/${envoy_service} 8080:80
EOF

  print_section "port-forward 이후 curl 테스트"
  cat <<'EOF'
curl -i \
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
  http://localhost:8080/v1/chat/completions

성공 기준:
- HTTP/1.1 200 OK
- 응답 헤더에 x-model: some-cool-self-hosted-model 포함
- 응답 body에 assistant message 포함
EOF
}

main "$@"
