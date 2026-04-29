#!/usr/bin/env bash
set -euo pipefail

# Envoy AI Gateway v0.5 extproc 소스를 기반으로 Memory PoC image를 만든다.
# Redis 연동 전/후 검증을 모두 지원한다.

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
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	extprocv3 "github.com/envoyproxy/go-control-plane/envoy/service/ext_proc/v3"
)

const memoryPOCDummyEnv = "MEMORY_POC_DUMMY_INJECTION"
const memoryPOCRedisEnv = "MEMORY_POC_REDIS_ENABLED"

type memoryMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

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

func applyMemoryPOCRequestMutation(bodyMutation *extprocv3.BodyMutation, originalBody []byte, requestHeaders map[string]string, logger *slog.Logger) *extprocv3.BodyMutation {
	bodyMutation = applyMemoryPOCDummyMutation(bodyMutation, originalBody, logger)
	if os.Getenv(memoryPOCRedisEnv) != "true" {
		return bodyMutation
	}

	sessionID := memoryPOCHeader(requestHeaders, "x-session-id")
	if sessionID == "" {
		logger.Warn("memory poc skipped redis history lookup because x-session-id is missing")
		return bodyMutation
	}

	history, err := memoryPOCLoadHistory(sessionID)
	if err != nil {
		logger.Warn("memory poc failed to load redis history", "session_id", sessionID, "error", err)
		return bodyMutation
	}
	if len(history) == 0 {
		logger.Info("memory poc redis history empty", "session_id", sessionID)
		return bodyMutation
	}

	bodyBytes := originalBody
	if mutatedBody := bodyMutation.GetBody(); len(mutatedBody) > 0 {
		bodyBytes = mutatedBody
	}

	var requestBody map[string]any
	if err := json.Unmarshal(bodyBytes, &requestBody); err != nil {
		logger.Warn("memory poc failed to parse request body for redis merge", "error", err)
		return bodyMutation
	}
	messages, ok := requestBody["messages"].([]any)
	if !ok {
		logger.Warn("memory poc request body has no messages array for redis merge")
		return bodyMutation
	}

	merged := make([]any, 0, len(history)+len(messages))
	for _, msg := range history {
		merged = append(merged, map[string]any{"role": msg.Role, "content": msg.Content})
	}
	merged = append(merged, messages...)
	requestBody["messages"] = merged

	mutatedBody, err := json.Marshal(requestBody)
	if err != nil {
		logger.Warn("memory poc failed to marshal redis merged body", "error", err)
		return bodyMutation
	}

	logger.Info("memory poc merged redis history", "session_id", sessionID, "history_messages", len(history), "request_messages", len(messages), "mutated_messages", len(merged))
	return &extprocv3.BodyMutation{Mutation: &extprocv3.BodyMutation_Body{Body: mutatedBody}}
}

func storeMemoryPOCResponse(originalRequestBody []byte, responseBody []byte, requestHeaders map[string]string, logger *slog.Logger) {
	if os.Getenv(memoryPOCRedisEnv) != "true" {
		return
	}

	sessionID := memoryPOCHeader(requestHeaders, "x-session-id")
	if sessionID == "" {
		logger.Warn("memory poc skipped redis store because x-session-id is missing")
		return
	}

	userMessages, err := memoryPOCUserMessages(originalRequestBody)
	if err != nil {
		logger.Warn("memory poc failed to parse request messages for redis store", "session_id", sessionID, "error", err)
		return
	}
	assistantMessages, err := memoryPOCAssistantMessages(responseBody)
	if err != nil {
		logger.Warn("memory poc failed to parse assistant message for redis store", "session_id", sessionID, "error", err)
		return
	}

	if len(userMessages) == 0 && len(assistantMessages) == 0 {
		logger.Warn("memory poc skipped redis store because no messages were extracted", "session_id", sessionID)
		return
	}

	history, err := memoryPOCLoadHistory(sessionID)
	if err != nil {
		logger.Warn("memory poc failed to load existing history before store", "session_id", sessionID, "error", err)
		history = nil
	}
	history = append(history, userMessages...)
	history = append(history, assistantMessages...)
	history = memoryPOCTrimHistory(history)

	if err := memoryPOCStoreHistory(sessionID, history); err != nil {
		logger.Warn("memory poc failed to store redis history", "session_id", sessionID, "error", err)
		return
	}
	logger.Info("memory poc stored redis history", "session_id", sessionID, "stored_messages", len(history), "added_user_messages", len(userMessages), "added_assistant_messages", len(assistantMessages))
}

func memoryPOCHeader(headers map[string]string, name string) string {
	for key, value := range headers {
		if strings.EqualFold(key, name) {
			return value
		}
	}
	return ""
}

func memoryPOCUserMessages(body []byte) ([]memoryMessage, error) {
	var request struct {
		Messages []memoryMessage `json:"messages"`
	}
	if err := json.Unmarshal(body, &request); err != nil {
		return nil, err
	}
	result := make([]memoryMessage, 0, len(request.Messages))
	for _, msg := range request.Messages {
		if msg.Role == "user" && msg.Content != "" {
			result = append(result, msg)
		}
	}
	return result, nil
}

func memoryPOCAssistantMessages(body []byte) ([]memoryMessage, error) {
	var response struct {
		Choices []struct {
			Message memoryMessage `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(body, &response); err != nil {
		return nil, err
	}
	result := make([]memoryMessage, 0, len(response.Choices))
	for _, choice := range response.Choices {
		if choice.Message.Role == "assistant" && choice.Message.Content != "" {
			result = append(result, choice.Message)
		}
	}
	return result, nil
}

func memoryPOCTrimHistory(history []memoryMessage) []memoryMessage {
	maxMessages := memoryPOCEnvInt("MEMORY_MAX_HISTORY_MESSAGES", 20)
	if maxMessages <= 0 || len(history) <= maxMessages {
		return history
	}
	return history[len(history)-maxMessages:]
}

func memoryPOCLoadHistory(sessionID string) ([]memoryMessage, error) {
	value, err := memoryPOCRedisCommand("GET", memoryPOCKey(sessionID))
	if err != nil {
		if errors.Is(err, redisNil) {
			return nil, nil
		}
		return nil, err
	}
	if value == "" {
		return nil, nil
	}
	var history []memoryMessage
	if err := json.Unmarshal([]byte(value), &history); err != nil {
		return nil, err
	}
	return history, nil
}

func memoryPOCStoreHistory(sessionID string, history []memoryMessage) error {
	payload, err := json.Marshal(history)
	if err != nil {
		return err
	}
	ttl := memoryPOCEnvInt("MEMORY_TTL_SECONDS", 3600)
	_, err = memoryPOCRedisCommand("SETEX", memoryPOCKey(sessionID), strconv.Itoa(ttl), string(payload))
	return err
}

func memoryPOCKey(sessionID string) string {
	return "memory:chat:" + sessionID
}

func memoryPOCEnvInt(name string, fallback int) int {
	value := os.Getenv(name)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

var redisNil = errors.New("redis nil")

func memoryPOCRedisCommand(args ...string) (string, error) {
	addr, err := memoryPOCRedisAddr()
	if err != nil {
		return "", err
	}
	conn, err := net.DialTimeout("tcp", addr, 2*time.Second)
	if err != nil {
		return "", err
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(3 * time.Second))

	var request bytes.Buffer
	request.WriteString(fmt.Sprintf("*%d\r\n", len(args)))
	for _, arg := range args {
		request.WriteString(fmt.Sprintf("$%d\r\n%s\r\n", len(arg), arg))
	}
	if _, err := conn.Write(request.Bytes()); err != nil {
		return "", err
	}
	return readRedisResponse(bufio.NewReader(conn))
}

func memoryPOCRedisAddr() (string, error) {
	rawURL := os.Getenv("REDIS_URL")
	if rawURL == "" {
		return "", errors.New("REDIS_URL is empty")
	}
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return "", err
	}
	if parsed.Scheme != "redis" {
		return "", fmt.Errorf("unsupported redis scheme: %s", parsed.Scheme)
	}
	return parsed.Host, nil
}

func readRedisResponse(reader *bufio.Reader) (string, error) {
	prefix, err := reader.ReadByte()
	if err != nil {
		return "", err
	}
	line, err := reader.ReadString('\n')
	if err != nil {
		return "", err
	}
	line = strings.TrimSuffix(strings.TrimSuffix(line, "\n"), "\r")

	switch prefix {
	case '+':
		return line, nil
	case '-':
		return "", errors.New(line)
	case ':':
		return line, nil
	case '$':
		size, err := strconv.Atoi(line)
		if err != nil {
			return "", err
		}
		if size == -1 {
			return "", redisNil
		}
		data := make([]byte, size+2)
		if _, err := io.ReadFull(reader, data); err != nil {
			return "", err
		}
		return string(data[:size]), nil
	default:
		return "", fmt.Errorf("unsupported redis response prefix: %q", prefix)
	}
}
GO

  python3 - "${BUILD_DIR}/internal/extproc/processor_impl.go" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = "\tbodyMutation = applyBodyMutation(u.bodyMutator, bodyMutation,\n\t\tu.parent.originalRequestBodyRaw, forceBodyMutation, u.logger)\n"
replacement = needle + "\tbodyMutation = applyMemoryPOCRequestMutation(bodyMutation, u.parent.originalRequestBodyRaw, u.requestHeaders, u.logger)\n"
if replacement not in text:
    if needle not in text:
        raise SystemExit("patch target not found")
    text = text.replace(needle, replacement, 1)
path.write_text(text)
PY

  python3 - "${BUILD_DIR}/internal/extproc/processor_impl.go" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = """\tnewHeaders, newBody, tokenUsage, responseModel, err := u.translator.ResponseBody(u.responseHeaders, decodingResult.reader, body.EndOfStream, u.parent.span)
\tif err != nil {
\t\treturn nil, fmt.Errorf("failed to transform response: %w", err)
\t}
\theaderMutation, bodyMutation := mutationsFromTranslationResult(newHeaders, newBody)
"""
replacement = needle + """\tif body.EndOfStream {
\t\tresponseBody := body.Body
\t\tif mutatedBody := bodyMutation.GetBody(); len(mutatedBody) > 0 {
\t\t\tresponseBody = mutatedBody
\t\t}
\t\tstoreMemoryPOCResponse(u.parent.originalRequestBodyRaw, responseBody, u.requestHeaders, u.logger)
\t}
"""
if replacement not in text:
    if needle not in text:
        raise SystemExit("response patch target not found")
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
