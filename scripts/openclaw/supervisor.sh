#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_SCRIPT="$ROOT_DIR/scripts/openclaw/config.cjs"
RUNTIME_DIR="$ROOT_DIR/.openclaw/runtime"
STATE_FILE="$RUNTIME_DIR/supervisor-state.json"
LANE_STATE_FILE="$RUNTIME_DIR/lane-state.json"
DISPATCH_HISTORY_FILE="$RUNTIME_DIR/dispatch-history.jsonl"
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

status_diff_paths_json() {
  local before_status="$1"
  local after_status="$2"

  node -e '
    const before = new Set((process.argv[1] || "").split("\n").filter(Boolean));
    const after = (process.argv[2] || "").split("\n").filter(Boolean);
    const paths = [];

    for (const line of after) {
      if (before.has(line)) continue;
      const match = line.match(/^.. (.+)$/);
      if (!match) continue;
      const rawPath = match[1];
      const normalized = rawPath.includes(" -> ") ? rawPath.split(" -> ").pop() : rawPath;
      if (!paths.includes(normalized)) paths.push(normalized);
    }

    process.stdout.write(JSON.stringify(paths));
  ' "$before_status" "$after_status"
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

read_state_object_json() {
  local field="$1"
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const field = process.argv[2];
    if (!fs.existsSync(path)) process.exit(0);
    const payload = JSON.parse(fs.readFileSync(path, "utf8"));
    const value = payload[field];
    if (value === undefined || value === null) process.exit(0);
    process.stdout.write(JSON.stringify(value));
  ' "$STATE_FILE" "$field"
}

write_state_json() {
  local now_ms="$1"
  local now_iso="$2"
  local signatures_json="$3"
  local session_updated_json="$4"
  local last_activity_at="$5"
  local last_dispatch_at="$6"
  local last_dispatched_role="$7"
  local dispatch_count="$8"
  local decision="$9"
  local reason="${10}"

  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const payload = {
      updatedAtMs: Number(process.argv[2]),
      updatedAtIso: process.argv[3],
      signatures: JSON.parse(process.argv[4]),
      sessionUpdatedAt: JSON.parse(process.argv[5]),
      lastActivityAt: Number(process.argv[6]),
      lastDispatchAt: Number(process.argv[7]),
      lastDispatchedRole: process.argv[8],
      dispatchCount: Number(process.argv[9]),
      lastDecision: process.argv[10],
      lastReason: process.argv[11]
    };
    fs.writeFileSync(path, JSON.stringify(payload, null, 2) + "\n", "utf8");
  ' "$STATE_FILE" "$now_ms" "$now_iso" "$signatures_json" "$session_updated_json" "$last_activity_at" "$last_dispatch_at" "$last_dispatched_role" "$dispatch_count" "$decision" "$reason"
}

read_lane_json() {
  local role="$1"
  local field="$2"
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const role = process.argv[2];
    const field = process.argv[3];
    if (!fs.existsSync(path)) process.exit(0);
    const payload = JSON.parse(fs.readFileSync(path, "utf8"));
    const lane = payload[role] || {};
    const value = lane[field];
    if (value === undefined || value === null) process.exit(0);
    process.stdout.write(String(value));
  ' "$LANE_STATE_FILE" "$role" "$field"
}

write_lane_json() {
  local role="$1"
  local now_ms="$2"
  local now_iso="$3"
  local signature="$4"
  local status="$5"
  local goal="$6"
  local changed="$7"
  local verified="$8"
  local next_step="$9"
  local handoff="${10}"
  local session_id="${11}"
  local session_total_tokens="${12}"
  local session_context_tokens="${13}"
  local session_updated_at="${14}"

  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const role = process.argv[2];
    const payload = fs.existsSync(path) ? JSON.parse(fs.readFileSync(path, "utf8")) : {};
    payload[role] = {
      updatedAtMs: Number(process.argv[3]),
      updatedAtIso: process.argv[4],
      signature: process.argv[5],
      status: process.argv[6],
      goal: process.argv[7],
      changed: process.argv[8],
      verified: process.argv[9],
      next: process.argv[10],
      handoff: process.argv[11],
      sessionId: process.argv[12],
      sessionTotalTokens: Number(process.argv[13]),
      sessionContextTokens: Number(process.argv[14]),
      sessionUpdatedAt: Number(process.argv[15])
    };
    fs.writeFileSync(path, JSON.stringify(payload, null, 2) + "\n", "utf8");
  ' "$LANE_STATE_FILE" "$role" "$now_ms" "$now_iso" "$signature" "$status" "$goal" "$changed" "$verified" "$next_step" "$handoff" "$session_id" "$session_total_tokens" "$session_context_tokens" "$session_updated_at"
}

latest_session_meta_json() {
  local session_store="$1"
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const empty = { sessionId: "", updatedAt: 0, totalTokens: 0, contextTokens: 272000 };
    if (!fs.existsSync(path)) {
      process.stdout.write(JSON.stringify(empty));
      process.exit(0);
    }
    const payload = JSON.parse(fs.readFileSync(path, "utf8"));
    const sessions = Array.isArray(payload.sessions)
      ? payload.sessions
      : Array.isArray(payload)
        ? payload
        : Array.isArray(payload.items)
          ? payload.items
          : Object.values(payload);
    const chosen = sessions
      .slice()
      .sort((a, b) => (Number(b.updatedAt) || 0) - (Number(a.updatedAt) || 0))[0] || null;
    if (!chosen) {
      process.stdout.write(JSON.stringify(empty));
      process.exit(0);
    }
    process.stdout.write(JSON.stringify({
      sessionId: chosen.sessionId || "",
      updatedAt: Number(chosen.updatedAt) || 0,
      totalTokens: Number(chosen.totalTokens) || 0,
      contextTokens: Number(chosen.contextTokens) || 272000
    }));
  ' "$session_store"
}

json_field() {
  local json_payload="$1"
  local field="$2"
  node -e '
    const payload = JSON.parse(process.argv[1]);
    const value = payload[process.argv[2]];
    if (value === undefined || value === null) process.exit(0);
    process.stdout.write(String(value));
  ' "$json_payload" "$field"
}

parse_dispatch_report_json() {
  local output_text="$1"
  node -e '
    const text = process.argv[1] || "";
    const fields = ["STATUS", "GOAL", "CHANGED", "VERIFIED", "NEXT", "HANDOFF"];
    const result = {
      status: "continue",
      goal: "",
      changed: "",
      verified: "",
      next: "",
      handoff: ""
    };
    for (const field of fields) {
      const matches = [...text.matchAll(new RegExp(`^${field}:\\s*(.*)$`, "gmi"))];
      if (matches.length === 0) continue;
      const value = matches[matches.length - 1][1].trim();
      const key = field.toLowerCase();
      if (key === "status") {
        const normalized = value.toLowerCase();
        result.status = ["continue", "done", "blocked", "defer"].includes(normalized) ? normalized : "continue";
      } else {
        result[key] = value;
      }
    }
    process.stdout.write(JSON.stringify(result));
  ' "$output_text"
}

append_dispatch_history() {
  local dispatched_at_ms="$1"
  local dispatched_at_iso="$2"
  local role="$3"
  local exit_code="$4"
  local session_id="$5"
  local prompt="$6"
  local changed_paths_json="$7"
  local report_json="$8"
  local output_text="$9"

  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const changedPaths = JSON.parse(process.argv[2]);
    const report = JSON.parse(process.argv[3]);
    const outputText = process.argv[4] || "";
    const prompt = process.argv[5] || "";
    const payload = {
      dispatchedAtMs: Number(process.argv[6]),
      dispatchedAtIso: process.argv[7],
      role: process.argv[8],
      exitCode: Number(process.argv[9]),
      sessionId: process.argv[10],
      changedPaths,
      prompt,
      status: report.status || "continue",
      goal: report.goal || "",
      changedSummary: report.changed || "",
      verifiedSummary: report.verified || "",
      nextSummary: report.next || "",
      handoffSummary: report.handoff || "",
      outputExcerpt: outputText.split("\n").filter(Boolean).slice(-20).join("\n")
    };
    fs.appendFileSync(path, JSON.stringify(payload) + "\n", "utf8");
  ' "$DISPATCH_HISTORY_FILE" "$changed_paths_json" "$report_json" "$output_text" "$prompt" "$dispatched_at_ms" "$dispatched_at_iso" "$role" "$exit_code" "$session_id"
}

json_from_role_map() {
  local map_name="$1"
  declare -n role_map="$map_name"
  local pairs=()
  local role
  for role in "${ROLE_KEYS[@]}"; do
    pairs+=("${role}"$'\t'"${role_map[$role]-}")
  done

  node -e '
    const obj = {};
    for (const pair of process.argv.slice(1)) {
      const tabIndex = pair.indexOf("\t");
      if (tabIndex === -1) {
        obj[pair] = "";
        continue;
      }
      const key = pair.slice(0, tabIndex);
      const value = pair.slice(tabIndex + 1);
      obj[key] = value;
    }
    process.stdout.write(JSON.stringify(obj));
  ' "${pairs[@]}"
}

pick_role() {
  local previous_role="$1"
  local ages_json="$2"
  local terminals_json="$3"

  node -e '
    const roles = (process.argv[1] || "").split("\n").filter(Boolean);
    const previousRole = process.argv[2] || "";
    const ages = JSON.parse(process.argv[3]);
    const terminals = JSON.parse(process.argv[4]);
    const available = roles.filter((role) => String(terminals[role] || "0") !== "1");

    if (available.length === 0) {
      process.stdout.write("none");
      process.exit(0);
    }

    const bestAge = available.reduce((best, role) => {
      const age = Number(ages[role] || 0);
      return age > best ? age : best;
    }, Number.NEGATIVE_INFINITY);

    const top = available.filter((role) => Number(ages[role] || 0) === bestAge);
    if (top.length === 1) {
      process.stdout.write(top[0]);
      process.exit(0);
    }

    const previousIndex = top.indexOf(previousRole);
    if (previousIndex >= 0) {
      process.stdout.write(top[(previousIndex + 1) % top.length]);
      process.exit(0);
    }

    process.stdout.write(top[0]);
  ' "$(printf '%s\n' "${ROLE_KEYS[@]}")" "$previous_role" "$ages_json" "$terminals_json"
}

dispatch_role() {
  local role="$1"
  local prompt="$2"
  bash "$ROOT_DIR/scripts/openclaw/dispatch-agent.sh" "$role" "$prompt" --thinking high
}

mapfile -t ROLE_KEYS < <(node "$CONFIG_SCRIPT" agent-keys)
if [ "${#ROLE_KEYS[@]}" -eq 0 ]; then
  printf 'No agents configured in .openclaw/project.json\n' >&2
  exit 1
fi

declare -A STATUS_BY_ROLE=()
declare -A SIGNATURE_BY_ROLE=()
declare -A AGENT_ID_BY_ROLE=()
declare -A SESSION_UPDATED_BY_ROLE=()
declare -A LANE_STATUS_BY_ROLE=()
declare -A LANE_SIGNATURE_BY_ROLE=()
declare -A TERMINAL_BY_ROLE=()

for ROLE in "${ROLE_KEYS[@]}"; do
  ROLE_PATHS=()
  while IFS= read -r line; do
    [ -n "$line" ] && ROLE_PATHS+=("$line")
  done < <(node "$CONFIG_SCRIPT" agent-paths "$ROLE")

  STATUS_BY_ROLE["$ROLE"]="$(path_status "${ROLE_PATHS[@]}")"
  SIGNATURE_BY_ROLE["$ROLE"]="$(hash_status "${STATUS_BY_ROLE[$ROLE]}")"
  AGENT_ID_BY_ROLE["$ROLE"]="$(node "$CONFIG_SCRIPT" agent-id "$ROLE")"

  SESSION_META="$(latest_session_meta_json "$OPENCLAW_HOME/agents/${AGENT_ID_BY_ROLE[$ROLE]}/sessions/sessions.json")"
  SESSION_UPDATED_AT="$(json_field "$SESSION_META" updatedAt)"
  SESSION_UPDATED_BY_ROLE["$ROLE"]="${SESSION_UPDATED_AT:-0}"

  LANE_STATUS_BY_ROLE["$ROLE"]="$(read_lane_json "$ROLE" status)"
  LANE_SIGNATURE_BY_ROLE["$ROLE"]="$(read_lane_json "$ROLE" signature)"

  TERMINAL_BY_ROLE["$ROLE"]="0"
  case "${LANE_STATUS_BY_ROLE[$ROLE]:-}" in
    done|blocked|defer)
      if [ "${LANE_SIGNATURE_BY_ROLE[$ROLE]:-}" = "${SIGNATURE_BY_ROLE[$ROLE]}" ]; then
        TERMINAL_BY_ROLE["$ROLE"]="1"
      fi
      ;;
  esac
done

CURRENT_SIGNATURES_JSON="$(json_from_role_map SIGNATURE_BY_ROLE)"
CURRENT_SESSIONS_JSON="$(json_from_role_map SESSION_UPDATED_BY_ROLE)"

NOW_MS="$(node -e 'process.stdout.write(String(Date.now()))')"
NOW_ISO="$(timestamp)"

PREV_SIGNATURES_JSON="$(read_state_object_json signatures)"
PREV_LAST_ACTIVITY_AT="$(read_state_json lastActivityAt)"
PREV_LAST_DISPATCH_AT="$(read_state_json lastDispatchAt)"
PREV_LAST_DISPATCHED_ROLE="$(read_state_json lastDispatchedRole)"
PREV_DISPATCH_COUNT="$(read_state_json dispatchCount)"

PREV_LAST_ACTIVITY_AT="${PREV_LAST_ACTIVITY_AT:-0}"
PREV_LAST_DISPATCH_AT="${PREV_LAST_DISPATCH_AT:-0}"
PREV_LAST_DISPATCHED_ROLE="${PREV_LAST_DISPATCHED_ROLE:-none}"
PREV_DISPATCH_COUNT="${PREV_DISPATCH_COUNT:-0}"

if [ -z "$PREV_SIGNATURES_JSON" ]; then
  write_state_json "$NOW_MS" "$NOW_ISO" "$CURRENT_SIGNATURES_JSON" "$CURRENT_SESSIONS_JSON" "$NOW_MS" "$PREV_LAST_DISPATCH_AT" "$PREV_LAST_DISPATCHED_ROLE" "$PREV_DISPATCH_COUNT" "primed" "Initial supervisor snapshot recorded"
  printf '[%s] primed: recorded initial repo snapshot\n' "$NOW_ISO"
  exit 0
fi

ACTIVITY_DETECTED=0
if [ "$DISPATCH_MODE" = "diff-only" ]; then
  ACTIVITY_DETECTED="$(node -e '
    const previous = JSON.parse(process.argv[1]);
    const current = JSON.parse(process.argv[2]);
    const roles = [...new Set([...Object.keys(previous), ...Object.keys(current)])];
    const changed = roles.some((role) => String(previous[role] || "") !== String(current[role] || ""));
    process.stdout.write(changed ? "1" : "0");
  ' "$PREV_SIGNATURES_JSON" "$CURRENT_SIGNATURES_JSON")"
fi

if [ "$ACTIVITY_DETECTED" -eq 1 ]; then
  write_state_json "$NOW_MS" "$NOW_ISO" "$CURRENT_SIGNATURES_JSON" "$CURRENT_SESSIONS_JSON" "$NOW_MS" "$PREV_LAST_DISPATCH_AT" "$PREV_LAST_DISPATCHED_ROLE" "$PREV_DISPATCH_COUNT" "activity" "Repo status changed since last tick"
  printf '[%s] activity: repo status changed, no dispatch\n' "$NOW_ISO"
  exit 0
fi

INACTIVE_FOR_MS=$((NOW_MS - PREV_LAST_ACTIVITY_AT))
STALL_THRESHOLD_MS=$((STALL_SECONDS * 1000))
DISPATCH_COOLDOWN_MS=$((DISPATCH_COOLDOWN_SECONDS * 1000))
SINCE_LAST_DISPATCH_MS=$((NOW_MS - PREV_LAST_DISPATCH_AT))

if [ "$INACTIVE_FOR_MS" -lt "$STALL_THRESHOLD_MS" ]; then
  write_state_json "$NOW_MS" "$NOW_ISO" "$CURRENT_SIGNATURES_JSON" "$CURRENT_SESSIONS_JSON" "$PREV_LAST_ACTIVITY_AT" "$PREV_LAST_DISPATCH_AT" "$PREV_LAST_DISPATCHED_ROLE" "$PREV_DISPATCH_COUNT" "waiting" "Idle, but below stall threshold"
  printf '[%s] waiting: idle for %ss, below %ss stall threshold\n' "$NOW_ISO" "$((INACTIVE_FOR_MS / 1000))" "$STALL_SECONDS"
  exit 0
fi

if [ "$SINCE_LAST_DISPATCH_MS" -lt "$DISPATCH_COOLDOWN_MS" ]; then
  write_state_json "$NOW_MS" "$NOW_ISO" "$CURRENT_SIGNATURES_JSON" "$CURRENT_SESSIONS_JSON" "$PREV_LAST_ACTIVITY_AT" "$PREV_LAST_DISPATCH_AT" "$PREV_LAST_DISPATCHED_ROLE" "$PREV_DISPATCH_COUNT" "cooldown" "Idle, but still in dispatch cooldown"
  printf '[%s] cooldown: idle, but last dispatch was %ss ago\n' "$NOW_ISO" "$((SINCE_LAST_DISPATCH_MS / 1000))"
  exit 0
fi

declare -A AGE_BY_ROLE=()
for ROLE in "${ROLE_KEYS[@]}"; do
  AGE_BY_ROLE["$ROLE"]=$((NOW_MS - ${SESSION_UPDATED_BY_ROLE[$ROLE]:-0}))
done

AGES_JSON="$(json_from_role_map AGE_BY_ROLE)"
TERMINALS_JSON="$(json_from_role_map TERMINAL_BY_ROLE)"
ROLE_TO_DISPATCH="$(pick_role "$PREV_LAST_DISPATCHED_ROLE" "$AGES_JSON" "$TERMINALS_JSON")"

if [ "$ROLE_TO_DISPATCH" = "none" ]; then
  write_state_json "$NOW_MS" "$NOW_ISO" "$CURRENT_SIGNATURES_JSON" "$CURRENT_SESSIONS_JSON" "$PREV_LAST_ACTIVITY_AT" "$PREV_LAST_DISPATCH_AT" "$PREV_LAST_DISPATCHED_ROLE" "$PREV_DISPATCH_COUNT" "terminal" "All lanes are terminal for the current repo state"
  printf '[%s] terminal: all lanes are done, blocked, or deferred for the current repo state\n' "$NOW_ISO"
  exit 0
fi

PROMPT="$(node "$CONFIG_SCRIPT" agent "$ROLE_TO_DISPATCH" idle_prompt)"
PROMPT="${PROMPT}

Finish with this exact compact report block:
STATUS: continue|done|blocked|defer
GOAL: one short sentence
CHANGED: one short sentence, or none
VERIFIED: one short sentence, or none
NEXT: one short sentence, or none
HANDOFF: one short sentence another fresh session could continue from

Keep each field brief and concrete."

ROLE_STATUS_BEFORE="${STATUS_BY_ROLE[$ROLE_TO_DISPATCH]}"

set +e
DISPATCH_OUTPUT="$(dispatch_role "$ROLE_TO_DISPATCH" "$PROMPT" 2>&1)"
DISPATCH_EXIT_CODE=$?
set -e

ROLE_PATHS_AFTER=()
while IFS= read -r line; do
  [ -n "$line" ] && ROLE_PATHS_AFTER+=("$line")
done < <(node "$CONFIG_SCRIPT" agent-paths "$ROLE_TO_DISPATCH")

ROLE_STATUS_AFTER="$(path_status "${ROLE_PATHS_AFTER[@]}")"
SESSION_META_AFTER="$(latest_session_meta_json "$OPENCLAW_HOME/agents/${AGENT_ID_BY_ROLE[$ROLE_TO_DISPATCH]}/sessions/sessions.json")"
ROLE_SIGNATURE="${SIGNATURE_BY_ROLE[$ROLE_TO_DISPATCH]}"

REPORT_JSON="$(parse_dispatch_report_json "$DISPATCH_OUTPUT")"
CHANGED_PATHS_JSON="$(status_diff_paths_json "$ROLE_STATUS_BEFORE" "$ROLE_STATUS_AFTER")"
SESSION_ID_AFTER="$(json_field "$SESSION_META_AFTER" sessionId)"
SESSION_TOTAL_TOKENS_AFTER="$(json_field "$SESSION_META_AFTER" totalTokens)"
SESSION_CONTEXT_TOKENS_AFTER="$(json_field "$SESSION_META_AFTER" contextTokens)"
SESSION_UPDATED_AT_AFTER="$(json_field "$SESSION_META_AFTER" updatedAt)"

append_dispatch_history "$NOW_MS" "$NOW_ISO" "$ROLE_TO_DISPATCH" "$DISPATCH_EXIT_CODE" "$SESSION_ID_AFTER" "$PROMPT" "$CHANGED_PATHS_JSON" "$REPORT_JSON" "$DISPATCH_OUTPUT"

REPORT_STATUS="$(json_field "$REPORT_JSON" status)"
REPORT_GOAL="$(json_field "$REPORT_JSON" goal)"
REPORT_CHANGED="$(json_field "$REPORT_JSON" changed)"
REPORT_VERIFIED="$(json_field "$REPORT_JSON" verified)"
REPORT_NEXT="$(json_field "$REPORT_JSON" next)"
REPORT_HANDOFF="$(json_field "$REPORT_JSON" handoff)"

write_lane_json "$ROLE_TO_DISPATCH" "$NOW_MS" "$NOW_ISO" "$ROLE_SIGNATURE" "${REPORT_STATUS:-continue}" "${REPORT_GOAL:-}" "${REPORT_CHANGED:-}" "${REPORT_VERIFIED:-}" "${REPORT_NEXT:-}" "${REPORT_HANDOFF:-}" "${SESSION_ID_AFTER:-}" "${SESSION_TOTAL_TOKENS_AFTER:-0}" "${SESSION_CONTEXT_TOKENS_AFTER:-272000}" "${SESSION_UPDATED_AT_AFTER:-0}"

if [ "$DISPATCH_EXIT_CODE" -eq 0 ]; then
  NEW_DISPATCH_COUNT=$((PREV_DISPATCH_COUNT + 1))
  write_state_json "$NOW_MS" "$NOW_ISO" "$CURRENT_SIGNATURES_JSON" "$CURRENT_SESSIONS_JSON" "$PREV_LAST_ACTIVITY_AT" "$NOW_MS" "$ROLE_TO_DISPATCH" "$NEW_DISPATCH_COUNT" "dispatched" "Idle threshold reached; dispatched ${ROLE_TO_DISPATCH} agent (${REPORT_STATUS:-continue})"
  printf '[%s] dispatched %s agent (status=%s)\n' "$NOW_ISO" "$ROLE_TO_DISPATCH" "${REPORT_STATUS:-continue}"
  printf '%s\n' "$DISPATCH_OUTPUT"
else
  write_state_json "$NOW_MS" "$NOW_ISO" "$CURRENT_SIGNATURES_JSON" "$CURRENT_SESSIONS_JSON" "$PREV_LAST_ACTIVITY_AT" "$PREV_LAST_DISPATCH_AT" "$PREV_LAST_DISPATCHED_ROLE" "$PREV_DISPATCH_COUNT" "error" "Dispatch failed for ${ROLE_TO_DISPATCH} agent"
  printf '[%s] error: failed to dispatch %s agent\n' "$NOW_ISO" "$ROLE_TO_DISPATCH" >&2
  printf '%s\n' "$DISPATCH_OUTPUT" >&2
  exit "$DISPATCH_EXIT_CODE"
fi
