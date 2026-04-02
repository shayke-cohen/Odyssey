#!/bin/zsh
set -euo pipefail

if [[ -z "${SRCROOT:-}" || -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  echo "build-local-agent-host.sh requires Xcode build environment variables" >&2
  exit 1
fi

PACKAGE_PATH="$SRCROOT/Packages/ClaudeStudioLocalAgent"
OUTPUT_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/local-agent/bin"
SWIFT_BIN="$(xcrun --find swift)"

mkdir -p "$OUTPUT_DIR"

"$SWIFT_BIN" build --package-path "$PACKAGE_PATH" --product ClaudeStudioLocalAgentHost

BIN_DIR="$("$SWIFT_BIN" build --package-path "$PACKAGE_PATH" --product ClaudeStudioLocalAgentHost --show-bin-path)"
HOST_BINARY="$BIN_DIR/ClaudeStudioLocalAgentHost"
if [[ ! -x "$HOST_BINARY" ]]; then
  echo "ClaudeStudioLocalAgentHost binary not found at $HOST_BINARY" >&2
  exit 1
fi

cp "$HOST_BINARY" "$OUTPUT_DIR/ClaudeStudioLocalAgentHost"
chmod +x "$OUTPUT_DIR/ClaudeStudioLocalAgentHost"
