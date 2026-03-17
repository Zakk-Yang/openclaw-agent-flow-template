#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_SCRIPT="$ROOT_DIR/scripts/openclaw/config.cjs"
SESSION_NAME="${SUPERVISOR_TMUX_SESSION:-$(node "$CONFIG_SCRIPT" project tmux_session)}"
STATE_FILE="$ROOT_DIR/.openclaw/runtime/supervisor-state.json"
LOG_FILE="$ROOT_DIR/.openclaw/runtime/supervisor.log"
DISPATCH_HISTORY_FILE="$ROOT_DIR/.openclaw/runtime/dispatch-history.jsonl"

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

if [ -f "$DISPATCH_HISTORY_FILE" ]; then
  printf '\nRecent dispatch history:\n'
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const lines = fs.readFileSync(path, "utf8").split("\n").filter(Boolean).slice(-5);
    for (const line of lines) {
      const entry = JSON.parse(line);
      const changed = Array.isArray(entry.changedPaths) ? entry.changedPaths : [];
      console.log(`- ${entry.dispatchedAtIso} role=${entry.role} exit=${entry.exitCode} changed=${changed.length}`);
      if (changed.length > 0) {
        console.log(`  files: ${changed.join(", ")}`);
      }
      if (entry.outputExcerpt) {
        console.log(`  summary: ${entry.outputExcerpt.split("\n")[0]}`);
      }
    }
  ' "$DISPATCH_HISTORY_FILE"
else
  printf '\nRecent dispatch history: missing\n'
fi
