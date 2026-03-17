#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_SCRIPT="$ROOT_DIR/scripts/openclaw/config.cjs"
SESSION_NAME="${SUPERVISOR_TMUX_SESSION:-$(node "$CONFIG_SCRIPT" project tmux_session)}"
STATE_FILE="$ROOT_DIR/.openclaw/runtime/supervisor-state.json"
LOG_FILE="$ROOT_DIR/.openclaw/runtime/supervisor.log"

if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  printf 'tmux session: running (%s)\n' "$SESSION_NAME"
else
  printf 'tmux session: stopped (%s)\n' "$SESSION_NAME"
fi

if [ -f "$STATE_FILE" ]; then
  printf '\nState file: %s\n' "$STATE_FILE"
  sed -n '1,220p' "$STATE_FILE"
else
  printf '\nState file: missing\n'
fi

if [ -f "$LOG_FILE" ]; then
  printf '\nRecent log:\n'
  tail -n 20 "$LOG_FILE"
else
  printf '\nRecent log: missing\n'
fi
