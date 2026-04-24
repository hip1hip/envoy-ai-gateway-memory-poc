#!/usr/bin/env bash
set -euo pipefail

# Envoy AI Gateway v0.5 migration 검증용 Kind 클러스터를 삭제한다.
# 삭제 작업이므로 실행 전 사용자 확인을 받는다.

CLUSTER_NAME="${CLUSTER_NAME:-aigw-v05}"

if ! command -v kind >/dev/null 2>&1; then
  echo "필수 명령을 찾을 수 없습니다: kind" >&2
  exit 1
fi

echo "삭제 대상 Kind 클러스터: ${CLUSTER_NAME}"

if ! kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  echo "대상 클러스터가 존재하지 않습니다: ${CLUSTER_NAME}"
  exit 0
fi

read -r -p "정말로 Kind 클러스터 '${CLUSTER_NAME}'를 삭제할까요? [y/N] " answer

case "${answer}" in
  y|Y|yes|YES)
    kind delete cluster --name "${CLUSTER_NAME}"
    echo "클러스터를 삭제했습니다: ${CLUSTER_NAME}"
    ;;
  *)
    echo "삭제를 취소했습니다."
    ;;
esac
