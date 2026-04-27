#!/usr/bin/env bash
set -euo pipefail

# Envoy AI Gateway v0.5 extproc 소스를 기반으로 Memory PoC skeleton image를 만든다.
# Redis 연동 전 단계로 request body 읽기와 dummy memory message 주입만 추가한다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

UPSTREAM_DIR="${UPSTREAM_DIR:-${HOME}/workspace/ai-gateway-v05}"
BUILD_ROOT="${BUILD_ROOT:-${REPO_ROOT}/.work}"
BUILD_DIR="${BUILD_DIR:-${BUILD_ROOT}/ai-gateway-v05-memory-extproc}"
IMAGE_NAME="${IMAGE_NAME:-envoy-ai-gateway-memory-extproc:v0.5.0-memory-skeleton}"
VERSION_STRING="${VERSION_STRING:-v0.5.0-0-gb40501fe}"

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "필수 명령을 찾을 수 없습니다: ${command_name}" >&2
    exit 1
  fi
}

main() {
  require_command docker
  require_command rsync

  if [[ ! -d "${UPSTREAM_DIR}" ]]; then
    echo "v0.5 upstream source가 없습니다: ${UPSTREAM_DIR}" >&2
    exit 1
  fi

  rm -rf "${BUILD_DIR}"
  mkdir -p "${BUILD_ROOT}"
  rsync -a --delete \
    --exclude .git \
    --exclude out \
    "${UPSTREAM_DIR}/" "${BUILD_DIR}/"

  cat >"${BUILD_DIR}/internal/extproc/memory_poc.go" <<'GO'
package extproc

import (
	"encoding/json"
	"log/slog"
	"os"

	extprocv3 "github.com/envoyproxy/go-control-plane/envoy/service/ext_proc/v3"
)

const memoryPOCDummyEnv = "MEMORY_POC_DUMMY_INJECTION"

func applyMemoryPOCDummyMutation(bodyMutation *extprocv3.BodyMutation, originalBody []byte, logger *slog.Logger) *extprocv3.BodyMutation {
	if os.Getenv(memoryPOCDummyEnv) != "true" {
		return bodyMutation
	}

	bodyBytes := originalBody
	if mutatedBody := bodyMutation.GetBody(); len(mutatedBody) > 0 {
		bodyBytes = mutatedBody
	}

	var requestBody map[string]any
	if err := json.Unmarshal(bodyBytes, &requestBody); err != nil {
		logger.Warn("memory poc failed to parse request body", "error", err)
		return bodyMutation
	}

	messages, ok := requestBody["messages"].([]any)
	if !ok {
		logger.Warn("memory poc request body has no messages array")
		return bodyMutation
	}

	dummyMessage := map[string]any{
		"role":    "system",
		"content": "[memory-poc] dummy short-term memory injected before Redis integration.",
	}
	requestBody["messages"] = append([]any{dummyMessage}, messages...)

	mutatedBody, err := json.Marshal(requestBody)
	if err != nil {
		logger.Warn("memory poc failed to marshal mutated body", "error", err)
		return bodyMutation
	}

	logger.Info("memory poc injected dummy message", "original_messages", len(messages), "mutated_messages", len(messages)+1)
	return &extprocv3.BodyMutation{Mutation: &extprocv3.BodyMutation_Body{Body: mutatedBody}}
}
GO

  python3 - "${BUILD_DIR}/internal/extproc/processor_impl.go" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = "\tbodyMutation = applyBodyMutation(u.bodyMutator, bodyMutation,\n\t\tu.parent.originalRequestBodyRaw, forceBodyMutation, u.logger)\n"
replacement = needle + "\tbodyMutation = applyMemoryPOCDummyMutation(bodyMutation, u.parent.originalRequestBodyRaw, u.logger)\n"
if replacement not in text:
    if needle not in text:
        raise SystemExit("patch target not found")
    text = text.replace(needle, replacement, 1)
path.write_text(text)
PY

  (
    cd "${BUILD_DIR}"
    mkdir -p out
    docker run --rm \
      -v "${BUILD_DIR}:/src" \
      -w /src \
      golang:1.25 \
      bash -lc "GOOS=linux GOARCH=amd64 CGO_ENABLED=0 /usr/local/go/bin/go build -ldflags '-X github.com/envoyproxy/ai-gateway/internal/version.version=${VERSION_STRING}' -o out/extproc-linux-amd64 ./cmd/extproc"
    docker build \
      --build-arg COMMAND_NAME=extproc \
      --build-arg TARGETOS=linux \
      --build-arg TARGETARCH=amd64 \
      -t "${IMAGE_NAME}" .
  )

  echo "IMAGE_NAME=${IMAGE_NAME}"
}

main "$@"
