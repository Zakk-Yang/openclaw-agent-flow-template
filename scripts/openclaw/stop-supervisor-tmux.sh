#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_SCRIPT="$ROOT_DIR/scripts/openclaw/config.cjs"
SESSION_NAME="${SUPERVISOR_TMUX_SESSION:-$(node "$CONFIG_SCRIPT" project tmux_session)}"

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux is not installed or not on PATH" >&2
  exit 1
fi

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  tmux kill-session -t "$SESSION_NAME"
  printf 'Stopped tmux session: %s\n' "$SESSION_NAME"
else
  printf 'tmux session not running: %s\n' "$SESSION_NAME"
fi
