#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_SCRIPT="$ROOT_DIR/scripts/openclaw/config.cjs"
RUNTIME_DIR="$ROOT_DIR/.openclaw/runtime"
LOG_FILE="$RUNTIME_DIR/supervisor.log"
INTERVAL_SECONDS="${SUPERVISOR_INTERVAL_SECONDS:-$(node "$CONFIG_SCRIPT" project heartbeat_interval_seconds)}"

mkdir -p "$RUNTIME_DIR"
cd "$ROOT_DIR"

while true; do
  NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  printf '[%s] heartbeat tick\n' "$NOW" | tee -a "$LOG_FILE"
  if bash "$ROOT_DIR/scripts/openclaw/supervisor.sh" 2>&1 | tee -a "$LOG_FILE"; then
    :
  else
    printf '[%s] supervisor run failed\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" | tee -a "$LOG_FILE"
  fi
  sleep "$INTERVAL_SECONDS"
done
