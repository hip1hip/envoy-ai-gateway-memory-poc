#!/usr/bin/env bash
set -euo pipefail

# Envoy AI Gateway v0.4 baseline 환경을 구성한다.
# 기준 환경: WSL2 Ubuntu + Docker Desktop + Kind

CLUSTER_NAME="${CLUSTER_NAME:-aigw-v04}"
KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-kindest/node:v1.32.0}"
KUBECTL_CONTEXT="kind-${CLUSTER_NAME}"
ENVOY_GATEWAY_VERSION="${ENVOY_GATEWAY_VERSION:-v1.5.4}"
AI_GATEWAY_VERSION="${AI_GATEWAY_VERSION:-v0.4.0}"
AI_GATEWAY_REPO_URL="${AI_GATEWAY_REPO_URL:-https://github.com/envoyproxy/ai-gateway.git}"
AI_GATEWAY_V04_DIR="${AI_GATEWAY_V04_DIR:-${HOME}/workspace/ai-gateway-v04}"
ENVOY_GATEWAY_VALUES_URL="https://raw.githubusercontent.com/envoyproxy/ai-gateway/${AI_GATEWAY_VERSION}/manifests/envoy-gateway-values.yaml"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  local command_name="$1"

  if ! command_exists "${command_name}"; then
    echo "필수 명령을 찾을 수 없습니다: ${command_name}" >&2
    exit 1
  fi
}

confirm_cluster_recreate() {
  local detected_version="$1"

  echo "기존 Kind 클러스터 '${CLUSTER_NAME}'가 Kubernetes ${detected_version}로 존재합니다."
  echo "v0.4 baseline은 ${KIND_NODE_IMAGE} 기준으로 검증되었습니다."
  read -r -p "기존 클러스터를 삭제하고 재생성할까요? [y/N] " answer

  case "${answer}" in
    y|Y|yes|YES)
      kind delete cluster --name "${CLUSTER_NAME}"
      kind create cluster --name "${CLUSTER_NAME}" --image "${KIND_NODE_IMAGE}"
      ;;
    *)
      echo "기존 클러스터를 유지합니다. 호환성 문제가 있으면 직접 삭제 후 다시 실행하세요."
      ;;
  esac
}

ensure_prerequisites() {
  echo "== 사전 도구 확인 =="
  require_command docker
  require_command kind
  require_command kubectl
  require_command helm
  require_command git
  require_command curl

  docker version >/dev/null
  docker ps >/dev/null
}

ensure_kind_cluster() {
  echo "== Kind 클러스터 확인 =="

  if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
    kubectl config use-context "${KUBECTL_CONTEXT}" >/dev/null
    local node_version
    node_version="$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}')"

    if [[ "${node_version}" != "v1.32.0" ]]; then
      confirm_cluster_recreate "${node_version}"
    else
      echo "기존 클러스터 '${CLUSTER_NAME}'를 재사용합니다. Kubernetes ${node_version}"
    fi
  else
    kind create cluster --name "${CLUSTER_NAME}" --image "${KIND_NODE_IMAGE}"
  fi

  kubectl config use-context "${KUBECTL_CONTEXT}" >/dev/null
  kubectl get nodes -o wide
}

install_envoy_gateway() {
  echo "== Envoy Gateway ${ENVOY_GATEWAY_VERSION} 설치 =="

  helm upgrade -i eg oci://docker.io/envoyproxy/gateway-helm \
    --version "${ENVOY_GATEWAY_VERSION}" \
    --namespace envoy-gateway-system \
    --create-namespace \
    -f "${ENVOY_GATEWAY_VALUES_URL}"

  kubectl wait --timeout=3m -n envoy-gateway-system \
    deployment/envoy-gateway \
    --for=condition=Available
}

install_ai_gateway() {
  echo "== Envoy AI Gateway ${AI_GATEWAY_VERSION} 설치 =="

  helm upgrade -i aieg-crd oci://docker.io/envoyproxy/ai-gateway-crds-helm \
    --version "${AI_GATEWAY_VERSION}" \
    --namespace envoy-ai-gateway-system \
    --create-namespace

  helm upgrade -i aieg oci://docker.io/envoyproxy/ai-gateway-helm \
    --version "${AI_GATEWAY_VERSION}" \
    --namespace envoy-ai-gateway-system \
    --create-namespace

  kubectl wait --timeout=3m -n envoy-ai-gateway-system \
    deployment/ai-gateway-controller \
    --for=condition=Available
}

ensure_ai_gateway_example_repo() {
  echo "== Envoy AI Gateway v0.4.0 example repo 준비 =="

  mkdir -p "$(dirname "${AI_GATEWAY_V04_DIR}")"

  if [[ -d "${AI_GATEWAY_V04_DIR}/.git" ]]; then
    echo "기존 repo를 재사용합니다: ${AI_GATEWAY_V04_DIR}"
    git -C "${AI_GATEWAY_V04_DIR}" fetch --tags origin "${AI_GATEWAY_VERSION}"
    git -C "${AI_GATEWAY_V04_DIR}" checkout "${AI_GATEWAY_VERSION}"
  else
    git clone --branch "${AI_GATEWAY_VERSION}" "${AI_GATEWAY_REPO_URL}" "${AI_GATEWAY_V04_DIR}"
  fi
}

apply_basic_example() {
  echo "== v0.4 basic example 적용 =="

  kubectl apply -f "${AI_GATEWAY_V04_DIR}/examples/basic/basic.yaml"
}

print_next_steps() {
  cat <<'EOF'

== 상태 확인 명령 ==
kubectl get nodes -o wide
kubectl get pods -n envoy-gateway-system
kubectl get pods -n envoy-ai-gateway-system
kubectl get gateway
kubectl describe gateway envoy-ai-gateway-basic
kubectl get aigatewayroute
kubectl describe aigatewayroute envoy-ai-gateway-basic
kubectl get aiservicebackend
kubectl describe aiservicebackend envoy-ai-gateway-basic-testupstream

== port-forward 준비 ==
export ENVOY_SERVICE=$(kubectl get svc -n envoy-gateway-system \
  --selector=gateway.envoyproxy.io/owning-gateway-namespace=default,gateway.envoyproxy.io/owning-gateway-name=envoy-ai-gateway-basic \
  -o jsonpath='{.items[0].metadata.name}')

echo "$ENVOY_SERVICE"

== 별도 터미널에서 실행 ==
kubectl port-forward -n envoy-gateway-system svc/$ENVOY_SERVICE 8080:80

== curl 검증 ==
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
EOF
}

main() {
  ensure_prerequisites
  ensure_kind_cluster
  install_envoy_gateway
  install_ai_gateway
  ensure_ai_gateway_example_repo
  apply_basic_example
  print_next_steps
}

main "$@"
