#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_SCRIPT="$ROOT_DIR/scripts/openclaw/config.cjs"
RUNTIME_DIR="$ROOT_DIR/.openclaw/runtime"
STATE_FILE="$RUNTIME_DIR/supervisor-state.json"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

INTERVAL_SECONDS="${SUPERVISOR_INTERVAL_SECONDS:-$(node "$CONFIG_SCRIPT" project heartbeat_interval_seconds)}"
STALL_SECONDS="${SUPERVISOR_STALL_SECONDS:-$(node "$CONFIG_SCRIPT" project stall_seconds)}"
DISPATCH_COOLDOWN_SECONDS="${SUPERVISOR_DISPATCH_COOLDOWN_SECONDS:-$(node "$CONFIG_SCRIPT" project dispatch_cooldown_seconds)}"
DISPATCH_MODE="$(node "$CONFIG_SCRIPT" project dispatch_mode)"

mkdir -p "$RUNTIME_DIR"
cd "$ROOT_DIR"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

hash_status() {
  local raw_status="$1"
  printf '%s' "$raw_status" | sha1sum | awk '{print $1}'
}

path_status() {
  git status --porcelain --untracked-files=all -- "$@" 2>/dev/null || true
}

latest_session_updated_at() {
  local session_store="$1"
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    let latest = 0;
    if (fs.existsSync(path)) {
      const payload = JSON.parse(fs.readFileSync(path, "utf8"));
      const sessions = Array.isArray(payload)
        ? payload
        : Array.isArray(payload.sessions)
          ? payload.sessions
          : Object.values(payload);
      for (const session of sessions) {
        const value = Number(session.updatedAt) || 0;
        if (value > latest) latest = value;
      }
    }
    process.stdout.write(String(latest));
  ' "$session_store"
}

read_state_json() {
  local field="$1"
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const field = process.argv[2];
    if (!fs.existsSync(path)) process.exit(0);
    const payload = JSON.parse(fs.readFileSync(path, "utf8"));
    const value = payload[field];
    if (value === undefined || value === null) process.exit(0);
    process.stdout.write(String(value));
  ' "$STATE_FILE" "$field"
}

write_state_json() {
  local now_ms="$1"
  local now_iso="$2"
  local primary_signature="$3"
  local secondary_signature="$4"
  local primary_updated_at="$5"
  local secondary_updated_at="$6"
  local last_activity_at="$7"
  local last_dispatch_at="$8"
  local last_dispatched_role="$9"
  local dispatch_count="${10}"
  local decision="${11}"
  local reason="${12}"

  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const payload = {
      updatedAtMs: Number(process.argv[2]),
      updatedAtIso: process.argv[3],
      primarySignature: process.argv[4],
      secondarySignature: process.argv[5],
      primarySessionUpdatedAt: Number(process.argv[6]),
      secondarySessionUpdatedAt: Number(process.argv[7]),
      lastActivityAt: Number(process.argv[8]),
      lastDispatchAt: Number(process.argv[9]),
      lastDispatchedRole: process.argv[10],
      dispatchCount: Number(process.argv[11]),
      lastDecision: process.argv[12],
      lastReason: process.argv[13]
    };
    fs.writeFileSync(path, JSON.stringify(payload, null, 2) + "\n", "utf8");
  ' "$STATE_FILE" "$now_ms" "$now_iso" "$primary_signature" "$secondary_signature" "$primary_updated_at" "$secondary_updated_at" "$last_activity_at" "$last_dispatch_at" "$last_dispatched_role" "$dispatch_count" "$decision" "$reason"
}

pick_role() {
  local previous_role="$1"
  local primary_age_ms="$2"
  local secondary_age_ms="$3"

  if [ "$primary_age_ms" -gt "$secondary_age_ms" ]; then
    printf 'primary'
    return
  fi

  if [ "$secondary_age_ms" -gt "$primary_age_ms" ]; then
    printf 'secondary'
    return
  fi

  if [ "$previous_role" = "primary" ]; then
    printf 'secondary'
  else
    printf 'primary'
  fi
}

dispatch_role() {
  local role="$1"
  local prompt="$2"
  bash "$ROOT_DIR/scripts/openclaw/dispatch-agent.sh" "$role" "$prompt" --thinking high
}

PRIMARY_PATHS=()
while IFS= read -r line; do
  [ -n "$line" ] && PRIMARY_PATHS+=("$line")
done < <(node "$CONFIG_SCRIPT" agent-paths primary)

SECONDARY_PATHS=()
while IFS= read -r line; do
  [ -n "$line" ] && SECONDARY_PATHS+=("$line")
done < <(node "$CONFIG_SCRIPT" agent-paths secondary)

PRIMARY_STATUS="$(path_status "${PRIMARY_PATHS[@]}")"
SECONDARY_STATUS="$(path_status "${SECONDARY_PATHS[@]}")"
PRIMARY_SIGNATURE="$(hash_status "$PRIMARY_STATUS")"
SECONDARY_SIGNATURE="$(hash_status "$SECONDARY_STATUS")"

PRIMARY_SESSION_UPDATED_AT="$(latest_session_updated_at "$OPENCLAW_HOME/agents/$(node "$CONFIG_SCRIPT" agent-id primary)/sessions/sessions.json")"
SECONDARY_SESSION_UPDATED_AT="$(latest_session_updated_at "$OPENCLAW_HOME/agents/$(node "$CONFIG_SCRIPT" agent-id secondary)/sessions/sessions.json")"

NOW_MS="$(node -e 'process.stdout.write(String(Date.now()))')"
NOW_ISO="$(timestamp)"

PREV_PRIMARY_SIGNATURE="$(read_state_json primarySignature)"
PREV_SECONDARY_SIGNATURE="$(read_state_json secondarySignature)"
PREV_LAST_ACTIVITY_AT="$(read_state_json lastActivityAt)"
PREV_LAST_DISPATCH_AT="$(read_state_json lastDispatchAt)"
PREV_LAST_DISPATCHED_ROLE="$(read_state_json lastDispatchedRole)"
PREV_DISPATCH_COUNT="$(read_state_json dispatchCount)"

PREV_LAST_ACTIVITY_AT="${PREV_LAST_ACTIVITY_AT:-0}"
PREV_LAST_DISPATCH_AT="${PREV_LAST_DISPATCH_AT:-0}"
PREV_LAST_DISPATCHED_ROLE="${PREV_LAST_DISPATCHED_ROLE:-none}"
PREV_DISPATCH_COUNT="${PREV_DISPATCH_COUNT:-0}"

if [ -z "$PREV_PRIMARY_SIGNATURE" ] && [ -z "$PREV_SECONDARY_SIGNATURE" ]; then
  write_state_json "$NOW_MS" "$NOW_ISO" "$PRIMARY_SIGNATURE" "$SECONDARY_SIGNATURE" "$PRIMARY_SESSION_UPDATED_AT" "$SECONDARY_SESSION_UPDATED_AT" "$NOW_MS" "$PREV_LAST_DISPATCH_AT" "$PREV_LAST_DISPATCHED_ROLE" "$PREV_DISPATCH_COUNT" "primed" "Initial supervisor snapshot recorded"
  printf '[%s] primed: recorded initial repo snapshot\n' "$NOW_ISO"
  exit 0
fi

ACTIVITY_DETECTED=0
if [ "$DISPATCH_MODE" = "diff-only" ]; then
  if [ "$PRIMARY_SIGNATURE" != "$PREV_PRIMARY_SIGNATURE" ] || [ "$SECONDARY_SIGNATURE" != "$PREV_SECONDARY_SIGNATURE" ]; then
    ACTIVITY_DETECTED=1
  fi
fi

if [ "$ACTIVITY_DETECTED" -eq 1 ]; then
  write_state_json "$NOW_MS" "$NOW_ISO" "$PRIMARY_SIGNATURE" "$SECONDARY_SIGNATURE" "$PRIMARY_SESSION_UPDATED_AT" "$SECONDARY_SESSION_UPDATED_AT" "$NOW_MS" "$PREV_LAST_DISPATCH_AT" "$PREV_LAST_DISPATCHED_ROLE" "$PREV_DISPATCH_COUNT" "activity" "Repo status changed since last tick"
  printf '[%s] activity: repo status changed, no dispatch\n' "$NOW_ISO"
  exit 0
fi

INACTIVE_FOR_MS=$((NOW_MS - PREV_LAST_ACTIVITY_AT))
STALL_THRESHOLD_MS=$((STALL_SECONDS * 1000))
DISPATCH_COOLDOWN_MS=$((DISPATCH_COOLDOWN_SECONDS * 1000))
SINCE_LAST_DISPATCH_MS=$((NOW_MS - PREV_LAST_DISPATCH_AT))

if [ "$INACTIVE_FOR_MS" -lt "$STALL_THRESHOLD_MS" ]; then
  write_state_json "$NOW_MS" "$NOW_ISO" "$PRIMARY_SIGNATURE" "$SECONDARY_SIGNATURE" "$PRIMARY_SESSION_UPDATED_AT" "$SECONDARY_SESSION_UPDATED_AT" "$PREV_LAST_ACTIVITY_AT" "$PREV_LAST_DISPATCH_AT" "$PREV_LAST_DISPATCHED_ROLE" "$PREV_DISPATCH_COUNT" "waiting" "Idle, but below stall threshold"
  printf '[%s] waiting: idle for %ss, below %ss stall threshold\n' "$NOW_ISO" "$((INACTIVE_FOR_MS / 1000))" "$STALL_SECONDS"
  exit 0
fi

if [ "$SINCE_LAST_DISPATCH_MS" -lt "$DISPATCH_COOLDOWN_MS" ]; then
  write_state_json "$NOW_MS" "$NOW_ISO" "$PRIMARY_SIGNATURE" "$SECONDARY_SIGNATURE" "$PRIMARY_SESSION_UPDATED_AT" "$SECONDARY_SESSION_UPDATED_AT" "$PREV_LAST_ACTIVITY_AT" "$PREV_LAST_DISPATCH_AT" "$PREV_LAST_DISPATCHED_ROLE" "$PREV_DISPATCH_COUNT" "cooldown" "Idle, but still in dispatch cooldown"
  printf '[%s] cooldown: idle, but last dispatch was %ss ago\n' "$NOW_ISO" "$((SINCE_LAST_DISPATCH_MS / 1000))"
  exit 0
fi

PRIMARY_AGE_MS=$((NOW_MS - PRIMARY_SESSION_UPDATED_AT))
SECONDARY_AGE_MS=$((NOW_MS - SECONDARY_SESSION_UPDATED_AT))
ROLE_TO_DISPATCH="$(pick_role "$PREV_LAST_DISPATCHED_ROLE" "$PRIMARY_AGE_MS" "$SECONDARY_AGE_MS")"
PROMPT="$(node "$CONFIG_SCRIPT" agent "$ROLE_TO_DISPATCH" idle_prompt)"

set +e
DISPATCH_OUTPUT="$(dispatch_role "$ROLE_TO_DISPATCH" "$PROMPT" 2>&1)"
DISPATCH_EXIT_CODE=$?
set -e

if [ "$DISPATCH_EXIT_CODE" -eq 0 ]; then
  NEW_DISPATCH_COUNT=$((PREV_DISPATCH_COUNT + 1))
  write_state_json "$NOW_MS" "$NOW_ISO" "$PRIMARY_SIGNATURE" "$SECONDARY_SIGNATURE" "$PRIMARY_SESSION_UPDATED_AT" "$SECONDARY_SESSION_UPDATED_AT" "$PREV_LAST_ACTIVITY_AT" "$NOW_MS" "$ROLE_TO_DISPATCH" "$NEW_DISPATCH_COUNT" "dispatched" "Idle threshold reached; dispatched ${ROLE_TO_DISPATCH} agent"
  printf '[%s] dispatched %s agent\n' "$NOW_ISO" "$ROLE_TO_DISPATCH"
  printf '%s\n' "$DISPATCH_OUTPUT"
else
  write_state_json "$NOW_MS" "$NOW_ISO" "$PRIMARY_SIGNATURE" "$SECONDARY_SIGNATURE" "$PRIMARY_SESSION_UPDATED_AT" "$SECONDARY_SESSION_UPDATED_AT" "$PREV_LAST_ACTIVITY_AT" "$PREV_LAST_DISPATCH_AT" "$PREV_LAST_DISPATCHED_ROLE" "$PREV_DISPATCH_COUNT" "error" "Dispatch failed for ${ROLE_TO_DISPATCH} agent"
  printf '[%s] error: failed to dispatch %s agent\n' "$NOW_ISO" "$ROLE_TO_DISPATCH" >&2
  printf '%s\n' "$DISPATCH_OUTPUT" >&2
  exit "$DISPATCH_EXIT_CODE"
fi
