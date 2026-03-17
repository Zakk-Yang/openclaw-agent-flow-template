#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_SCRIPT="$ROOT_DIR/scripts/openclaw/config.cjs"
SESSION_NAME="${SUPERVISOR_TMUX_SESSION:-$(node "$CONFIG_SCRIPT" project tmux_session)}"
RESTART_MODE="${1:-}"

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux is not installed or not on PATH" >&2
  exit 1
fi

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  if [ "$RESTART_MODE" = "--restart" ]; then
    tmux kill-session -t "$SESSION_NAME"
  else
    printf 'tmux session already running: %s\n' "$SESSION_NAME"
    printf 'Attach with: tmux attach -t %s\n' "$SESSION_NAME"
    exit 0
  fi
fi

tmux new-session -d -s "$SESSION_NAME" "cd '$ROOT_DIR' && bash scripts/openclaw/heartbeat-loop.sh"

printf 'Started tmux session: %s\n' "$SESSION_NAME"
printf 'Attach with: tmux attach -t %s\n' "$SESSION_NAME"
