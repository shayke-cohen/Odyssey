#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required"
  exit 1
fi

pick_port() {
  python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1', 0)); print(s.getsockname()[1]); s.close()"
}

json_field() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
value = payload
for part in sys.argv[2].split("."):
    if isinstance(value, list):
        value = value[int(part)]
    else:
        value = value[part]
if value is None:
    sys.exit(1)
if isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
PY
}

assert_snapshot_contains() {
  local snapshot="$1"
  local message_text="$2"
  local participant_name="${3:-}"

  python3 - "$snapshot" "$message_text" "$participant_name" <<'PY'
import json
import sys

snapshot = json.loads(sys.argv[1])
message = sys.argv[2]
participant = sys.argv[3]

messages = snapshot.get("messages", [])
if not any(item.get("text") == message for item in messages):
    raise SystemExit(f"missing message: {message}")

if participant:
    participants = snapshot.get("participants", [])
    if not any(item.get("displayName") == participant for item in participants):
        raise SystemExit(f"missing participant: {participant}")
PY
}

api_post() {
  local port="$1"
  local path="$2"
  local body="$3"
  local response_file
  response_file="$(mktemp)"
  local status
  status="$(
    curl -sS -o "$response_file" -w "%{http_code}" \
      -H "Content-Type: application/json" \
      -X POST "http://127.0.0.1:${port}${path}" \
      -d "$body"
  )"
  local response
  response="$(cat "$response_file")"
  rm -f "$response_file"

  if [[ "$status" != "200" ]]; then
    echo "POST ${path} failed with status ${status}: ${response}" >&2
    return 1
  fi

  printf '%s' "$response"
}

api_post_expect_failure() {
  local port="$1"
  local path="$2"
  local body="$3"
  local response_file
  response_file="$(mktemp)"
  local status
  status="$(
    curl -sS -o "$response_file" -w "%{http_code}" \
      -H "Content-Type: application/json" \
      -X POST "http://127.0.0.1:${port}${path}" \
      -d "$body"
  )"
  local response
  response="$(cat "$response_file")"
  rm -f "$response_file"

  if [[ "$status" == "200" ]]; then
    echo "POST ${path} unexpectedly succeeded: ${response}" >&2
    return 1
  fi

  printf '%s' "$response"
}

api_get() {
  local port="$1"
  local path="$2"
  local response_file
  response_file="$(mktemp)"
  local status
  status="$(
    curl -sS -o "$response_file" -w "%{http_code}" \
      "http://127.0.0.1:${port}${path}"
  )"
  local response
  response="$(cat "$response_file")"
  rm -f "$response_file"

  if [[ "$status" != "200" ]]; then
    echo "GET ${path} failed with status ${status}: ${response}" >&2
    return 1
  fi

  printf '%s' "$response"
}

wait_for_health() {
  local port="$1"
  for _ in $(seq 1 60); do
    if curl -sf "http://127.0.0.1:${port}/health" >/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/claudestudio-shared-room-api-derived}"
STORE_PATH="${STORE_PATH:-${TMPDIR:-/tmp}/claudestudio-shared-room-api-store-$$.plist}"
RUN_ID="api-smoke-$$"
HOST_INSTANCE="host-${RUN_ID}"
GUEST_INSTANCE="guest-${RUN_ID}"
HOST_API_PORT="${HOST_API_PORT:-$(pick_port)}"
GUEST_API_PORT="${GUEST_API_PORT:-$(pick_port)}"
HOST_APPXRAY_PORT="${HOST_APPXRAY_PORT:-$(pick_port)}"
GUEST_APPXRAY_PORT="${GUEST_APPXRAY_PORT:-$(pick_port)}"
while [[ "$GUEST_API_PORT" == "$HOST_API_PORT" ]]; do
  GUEST_API_PORT="$(pick_port)"
done
while [[ "$HOST_APPXRAY_PORT" == "$HOST_API_PORT" || "$HOST_APPXRAY_PORT" == "$GUEST_API_PORT" ]]; do
  HOST_APPXRAY_PORT="$(pick_port)"
done
while [[ "$GUEST_APPXRAY_PORT" == "$HOST_API_PORT" || "$GUEST_APPXRAY_PORT" == "$GUEST_API_PORT" || "$GUEST_APPXRAY_PORT" == "$HOST_APPXRAY_PORT" ]]; do
  GUEST_APPXRAY_PORT="$(pick_port)"
done

APP_BIN="${APP_BIN:-${DERIVED_DATA_PATH}/Build/Products/Debug/ClaudeStudio.app/Contents/MacOS/ClaudeStudio}"
HOST_LOG="${TMPDIR:-/tmp}/claudestudio-host-${RUN_ID}.log"
GUEST_LOG="${TMPDIR:-/tmp}/claudestudio-guest-${RUN_ID}.log"
HOST_PID=""
GUEST_PID=""

cleanup() {
  if [[ -n "$HOST_PID" ]] && kill -0 "$HOST_PID" 2>/dev/null; then
    kill "$HOST_PID" 2>/dev/null || true
    wait "$HOST_PID" 2>/dev/null || true
  fi
  if [[ -n "$GUEST_PID" ]] && kill -0 "$GUEST_PID" 2>/dev/null; then
    kill "$GUEST_PID" 2>/dev/null || true
    wait "$GUEST_PID" 2>/dev/null || true
  fi
  defaults delete "com.claudestudio.app.${HOST_INSTANCE}" >/dev/null 2>&1 || true
  defaults delete "com.claudestudio.app.${GUEST_INSTANCE}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ "${CLAUDESTUDIO_SKIP_BUILD:-0}" != "1" ]]; then
  echo "Building ClaudeStudio into ${DERIVED_DATA_PATH}"
  xcodebuild build \
    -project ClaudeStudio.xcodeproj \
    -scheme ClaudeStudio \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    -quiet
else
  echo "Skipping build and reusing app binary at ${APP_BIN}"
fi

if [[ ! -x "$APP_BIN" ]]; then
  echo "App binary not found at $APP_BIN" >&2
  exit 1
fi

defaults write "com.claudestudio.app.${HOST_INSTANCE}" "claudestudio.sharedRoom.userId" "host-user"
defaults write "com.claudestudio.app.${HOST_INSTANCE}" "claudestudio.sharedRoom.displayName" "Host User"
defaults write "com.claudestudio.app.${HOST_INSTANCE}" "claudestudio.autoConnectSidecar" -bool NO
defaults write "com.claudestudio.app.${HOST_INSTANCE}" "claudestudio.instanceWorkingDirectory" "$REPO_ROOT"
defaults write "com.claudestudio.app.${GUEST_INSTANCE}" "claudestudio.sharedRoom.userId" "guest-user"
defaults write "com.claudestudio.app.${GUEST_INSTANCE}" "claudestudio.sharedRoom.displayName" "Guest User"
defaults write "com.claudestudio.app.${GUEST_INSTANCE}" "claudestudio.autoConnectSidecar" -bool NO
defaults write "com.claudestudio.app.${GUEST_INSTANCE}" "claudestudio.instanceWorkingDirectory" "$REPO_ROOT"

echo "Launching host instance ${HOST_INSTANCE} on test API port ${HOST_API_PORT}"
env \
  CLAUDESTUDIO_SHARED_ROOM_BACKEND=local-test \
  CLAUDESTUDIO_SHARED_ROOM_STORE_PATH="$STORE_PATH" \
  CLAUDESTUDIO_TEST_API=1 \
  CLAUDESTUDIO_TEST_API_PORT="$HOST_API_PORT" \
  APPXRAY_SERVER_PORT="$HOST_APPXRAY_PORT" \
  "$APP_BIN" --instance "$HOST_INSTANCE" >"$HOST_LOG" 2>&1 &
HOST_PID=$!

wait_for_health "$HOST_API_PORT" || {
  echo "Host app did not become healthy. Log: $HOST_LOG" >&2
  exit 1
}

echo "Launching guest instance ${GUEST_INSTANCE} on test API port ${GUEST_API_PORT}"
env \
  CLAUDESTUDIO_SHARED_ROOM_BACKEND=local-test \
  CLAUDESTUDIO_SHARED_ROOM_STORE_PATH="$STORE_PATH" \
  CLAUDESTUDIO_TEST_API=1 \
  CLAUDESTUDIO_TEST_API_PORT="$GUEST_API_PORT" \
  APPXRAY_SERVER_PORT="$GUEST_APPXRAY_PORT" \
  "$APP_BIN" --instance "$GUEST_INSTANCE" >"$GUEST_LOG" 2>&1 &
GUEST_PID=$!

wait_for_health "$GUEST_API_PORT" || {
  echo "Guest app did not become healthy. Log: $GUEST_LOG" >&2
  exit 1
}

echo "Creating shared room from host"
CREATE_RESPONSE="$(api_post "$HOST_API_PORT" "/api/shared-room/create" '{"topic":"API Multi-App Room"}')"
ROOM_ID="$(json_field "$CREATE_RESPONSE" "roomId")"

echo "Creating single-use invite"
INVITE_RESPONSE="$(api_post "$HOST_API_PORT" "/api/shared-room/invite" "{\"roomId\":\"${ROOM_ID}\",\"recipientLabel\":\"Guest User\",\"expiresIn\":3600,\"singleUse\":true}")"
INVITE_ID="$(json_field "$INVITE_RESPONSE" "inviteId")"
INVITE_TOKEN="$(json_field "$INVITE_RESPONSE" "inviteToken")"

echo "Joining room from guest"
api_post "$GUEST_API_PORT" "/api/shared-room/join" "{\"roomId\":\"${ROOM_ID}\",\"inviteId\":\"${INVITE_ID}\",\"inviteToken\":\"${INVITE_TOKEN}\"}" >/dev/null

echo "Sending host message"
api_post "$HOST_API_PORT" "/api/shared-room/send" "{\"roomId\":\"${ROOM_ID}\",\"text\":\"hello from host\"}" >/dev/null
api_post "$GUEST_API_PORT" "/api/shared-room/refresh" "{\"roomId\":\"${ROOM_ID}\"}" >/dev/null
GUEST_STATE="$(api_get "$GUEST_API_PORT" "/api/shared-room/state?roomId=${ROOM_ID}")"
assert_snapshot_contains "$GUEST_STATE" "hello from host" "Host User"
assert_snapshot_contains "$GUEST_STATE" "hello from host" "Guest User"

echo "Sending guest message"
api_post "$GUEST_API_PORT" "/api/shared-room/send" "{\"roomId\":\"${ROOM_ID}\",\"text\":\"hello from guest\"}" >/dev/null
api_post "$HOST_API_PORT" "/api/shared-room/refresh" "{\"roomId\":\"${ROOM_ID}\"}" >/dev/null
HOST_STATE="$(api_get "$HOST_API_PORT" "/api/shared-room/state?roomId=${ROOM_ID}")"
assert_snapshot_contains "$HOST_STATE" "hello from guest" "Guest User"

echo "Verifying single-use invite rejection"
api_post_expect_failure "$GUEST_API_PORT" "/api/shared-room/join" "{\"roomId\":\"${ROOM_ID}\",\"inviteId\":\"${INVITE_ID}\",\"inviteToken\":\"${INVITE_TOKEN}\"}" >/dev/null

echo "Shared-room API smoke test passed."
