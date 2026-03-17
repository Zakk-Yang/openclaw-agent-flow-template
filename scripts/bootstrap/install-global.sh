#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_BIN_DIR="${OPENCLAW_FLOW_BIN_DIR:-$HOME/.local/bin}"
TARGET_CONFIG_DIR="${OPENCLAW_FLOW_CONFIG_DIR:-$HOME/.config/openclaw-agent-flow}"

mkdir -p "$TARGET_BIN_DIR" "$TARGET_CONFIG_DIR"

install -m 755 "$ROOT_DIR/scripts/bootstrap/new-agent-flow.sh" "$TARGET_BIN_DIR/new-agent-flow"
install -m 644 "$ROOT_DIR/prompt.txt" "$TARGET_CONFIG_DIR/prompt.txt"
install -m 644 "$ROOT_DIR/docs/global-setup.md" "$TARGET_CONFIG_DIR/README.md"

cat <<EOF
Installed global bootstrap layer:
  command: $TARGET_BIN_DIR/new-agent-flow
  prompt:  $TARGET_CONFIG_DIR/prompt.txt
  docs:    $TARGET_CONFIG_DIR/README.md

If $TARGET_BIN_DIR is on your PATH, you can now run:
  new-agent-flow my-project
EOF
