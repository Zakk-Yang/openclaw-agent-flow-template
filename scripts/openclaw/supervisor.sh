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
CONTEXT_ROLLOVER_PERCENT="${SUPERVISOR_CONTEXT_ROLLOVER_PERCENT:-95}"
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
  local rollover_count="${15}"
  local handoff_file="${16}"

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
      sessionUpdatedAt: Number(process.argv[15]),
      rolloverCount: Number(process.argv[16]),
      handoffFile: process.argv[17]
    };
    fs.writeFileSync(path, JSON.stringify(payload, null, 2) + "\n", "utf8");
  ' "$LANE_STATE_FILE" "$role" "$now_ms" "$now_iso" "$signature" "$status" "$goal" "$changed" "$verified" "$next_step" "$handoff" "$session_id" "$session_total_tokens" "$session_context_tokens" "$session_updated_at" "$rollover_count" "$handoff_file"
}

latest_session_meta_json() {
  local session_store="$1"
  local preferred_session_id="${2:-}"
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const preferred = process.argv[2];
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
    let chosen = null;
    if (preferred) {
      chosen = sessions.find((session) => session.sessionId === preferred) || null;
    }
    if (!chosen) {
      chosen = sessions
        .slice()
        .sort((a, b) => (Number(b.updatedAt) || 0) - (Number(a.updatedAt) || 0))[0] || null;
    }
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
  ' "$session_store" "$preferred_session_id"
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

role_handoff_file() {
  local role="$1"
  printf '%s/%s-handoff.md' "$RUNTIME_DIR" "$role"
}

append_status_contract() {
  cat <<'EOF'

Finish with this exact compact report block:
STATUS: continue|done|blocked|defer
GOAL: one short sentence
CHANGED: one short sentence, or none
VERIFIED: one short sentence, or none
NEXT: one short sentence, or none
HANDOFF: one short sentence another fresh session could continue from

Keep each field brief and concrete.
EOF
}

build_prompt() {
  local role="$1"
  local new_session="$2"
  local handoff_file="$3"
  local base_prompt
  base_prompt="$(node "$CONFIG_SCRIPT" agent "$role" idle_prompt)"

  if [ "$new_session" = "1" ] && [ -f "$handoff_file" ]; then
    cat <<EOF
${base_prompt}

This dispatch is starting a fresh session because the previous thread became too large. Use this handoff as the authoritative summary of prior work instead of relying on the old conversation:

<handoff_summary>
$(cat "$handoff_file")
</handoff_summary>
$(append_status_contract)
EOF
    return
  fi

  cat <<EOF
${base_prompt}
$(append_status_contract)
EOF
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

write_handoff_file() {
  local role="$1"
  local now_iso="$2"
  local session_id="$3"
  local report_json="$4"
  local output_file
  output_file="$(role_handoff_file "$role")"

  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const role = process.argv[2];
    const updatedAtIso = process.argv[3];
    const sessionId = process.argv[4];
    const report = JSON.parse(process.argv[5]);
    const title = role === "primary" ? "Primary Agent" : "Secondary Agent";
    const lines = [
      `# ${title} Handoff`,
      ``,
      `Updated: ${updatedAtIso}`,
      `Session: ${sessionId || "unknown"}`,
      `Status: ${report.status || "continue"}`,
      `Goal: ${report.goal || "none"}`,
      `Changed: ${report.changed || "none"}`,
      `Verified: ${report.verified || "none"}`,
      `Next: ${report.next || "none"}`,
      `Handoff: ${report.handoff || report.next || "none"}`
    ];
    fs.writeFileSync(path, lines.join("\n") + "\n", "utf8");
  ' "$output_file" "$role" "$now_iso" "$session_id" "$report_json"

  printf '%s' "$output_file"
}

append_dispatch_history() {
  local dispatched_at_ms="$1"
  local dispatched_at_iso="$2"
  local role="$3"
  local exit_code="$4"
  local session_id="$5"
  local rolled_over="$6"
  local prompt="$7"
  local changed_paths_json="$8"
  local report_json="$9"
  local output_text="${10}"

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
      rolledOverSession: process.argv[11] === "1",
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
  ' "$DISPATCH_HISTORY_FILE" "$changed_paths_json" "$report_json" "$output_text" "$prompt" "$dispatched_at_ms" "$dispatched_at_iso" "$role" "$exit_code" "$session_id" "$rolled_over"
}

generate_session_id() {
  node -e 'process.stdout.write(require("crypto").randomUUID())'
}

pick_role() {
  local previous_role="$1"
  local primary_age_ms="$2"
  local secondary_age_ms="$3"
  local primary_terminal="$4"
  local secondary_terminal="$5"

  if [ "$primary_terminal" = "1" ] && [ "$secondary_terminal" = "1" ]; then
    printf 'none'
    return
  fi

  if [ "$primary_terminal" = "1" ]; then
    printf 'secondary'
    return
  fi

  if [ "$secondary_terminal" = "1" ]; then
    printf 'primary'
    return
  fi

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
  local session_id="$3"
  bash "$ROOT_DIR/scripts/openclaw/dispatch-agent.sh" "$role" "$prompt" --session-id "$session_id" --thinking high
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

PRIMARY_AGENT_ID="$(node "$CONFIG_SCRIPT" agent-id primary)"
SECONDARY_AGENT_ID="$(node "$CONFIG_SCRIPT" agent-id secondary)"

PRIMARY_SESSION_ID_HINT="$(read_lane_json primary sessionId)"
SECONDARY_SESSION_ID_HINT="$(read_lane_json secondary sessionId)"

PRIMARY_SESSION_META="$(latest_session_meta_json "$OPENCLAW_HOME/agents/$PRIMARY_AGENT_ID/sessions/sessions.json" "$PRIMARY_SESSION_ID_HINT")"
SECONDARY_SESSION_META="$(latest_session_meta_json "$OPENCLAW_HOME/agents/$SECONDARY_AGENT_ID/sessions/sessions.json" "$SECONDARY_SESSION_ID_HINT")"

PRIMARY_SESSION_UPDATED_AT="$(json_field "$PRIMARY_SESSION_META" updatedAt)"
SECONDARY_SESSION_UPDATED_AT="$(json_field "$SECONDARY_SESSION_META" updatedAt)"

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

PRIMARY_LANE_STATUS="$(read_lane_json primary status)"
SECONDARY_LANE_STATUS="$(read_lane_json secondary status)"
PRIMARY_LANE_SIGNATURE="$(read_lane_json primary signature)"
SECONDARY_LANE_SIGNATURE="$(read_lane_json secondary signature)"

PRIMARY_TERMINAL=0
SECONDARY_TERMINAL=0
case "${PRIMARY_LANE_STATUS:-}" in
  done|blocked|defer)
    if [ "${PRIMARY_LANE_SIGNATURE:-}" = "$PRIMARY_SIGNATURE" ]; then
      PRIMARY_TERMINAL=1
    fi
    ;;
esac
case "${SECONDARY_LANE_STATUS:-}" in
  done|blocked|defer)
    if [ "${SECONDARY_LANE_SIGNATURE:-}" = "$SECONDARY_SIGNATURE" ]; then
      SECONDARY_TERMINAL=1
    fi
    ;;
esac

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
ROLE_TO_DISPATCH="$(pick_role "$PREV_LAST_DISPATCHED_ROLE" "$PRIMARY_AGE_MS" "$SECONDARY_AGE_MS" "$PRIMARY_TERMINAL" "$SECONDARY_TERMINAL")"

if [ "$ROLE_TO_DISPATCH" = "none" ]; then
  write_state_json "$NOW_MS" "$NOW_ISO" "$PRIMARY_SIGNATURE" "$SECONDARY_SIGNATURE" "$PRIMARY_SESSION_UPDATED_AT" "$SECONDARY_SESSION_UPDATED_AT" "$PREV_LAST_ACTIVITY_AT" "$PREV_LAST_DISPATCH_AT" "$PREV_LAST_DISPATCHED_ROLE" "$PREV_DISPATCH_COUNT" "terminal" "All lanes are terminal for the current repo state"
  printf '[%s] terminal: all lanes are done, blocked, or deferred for the current repo state\n' "$NOW_ISO"
  exit 0
fi

ROLLOVER_COUNT="$(read_lane_json "$ROLE_TO_DISPATCH" rolloverCount)"
ROLLOVER_COUNT="${ROLLOVER_COUNT:-0}"
ROLLED_OVER=0
NEW_SESSION=0

if [ "$ROLE_TO_DISPATCH" = "primary" ]; then
  ROLE_STATUS_BEFORE="$PRIMARY_STATUS"
  SESSION_META="$PRIMARY_SESSION_META"
else
  ROLE_STATUS_BEFORE="$SECONDARY_STATUS"
  SESSION_META="$SECONDARY_SESSION_META"
fi

SESSION_ID_TO_USE="$(json_field "$SESSION_META" sessionId)"
SESSION_TOTAL_TOKENS="$(json_field "$SESSION_META" totalTokens)"
SESSION_CONTEXT_TOKENS="$(json_field "$SESSION_META" contextTokens)"

if [ -z "$SESSION_ID_TO_USE" ]; then
  SESSION_ID_TO_USE="$(generate_session_id)"
  NEW_SESSION=1
fi

ROLLOVER_THRESHOLD=$((SESSION_CONTEXT_TOKENS * CONTEXT_ROLLOVER_PERCENT / 100))
if [ "$SESSION_TOTAL_TOKENS" -ge "$ROLLOVER_THRESHOLD" ]; then
  SESSION_ID_TO_USE="$(generate_session_id)"
  NEW_SESSION=1
  ROLLED_OVER=1
  ROLLOVER_COUNT=$((ROLLOVER_COUNT + 1))
fi

HANDOFF_FILE="$(role_handoff_file "$ROLE_TO_DISPATCH")"
PROMPT="$(build_prompt "$ROLE_TO_DISPATCH" "$NEW_SESSION" "$HANDOFF_FILE")"

set +e
DISPATCH_OUTPUT="$(dispatch_role "$ROLE_TO_DISPATCH" "$PROMPT" "$SESSION_ID_TO_USE" 2>&1)"
DISPATCH_EXIT_CODE=$?
set -e

if [ "$ROLE_TO_DISPATCH" = "primary" ]; then
  ROLE_STATUS_AFTER="$(path_status "${PRIMARY_PATHS[@]}")"
  SESSION_META_AFTER="$(latest_session_meta_json "$OPENCLAW_HOME/agents/$PRIMARY_AGENT_ID/sessions/sessions.json" "$SESSION_ID_TO_USE")"
  ROLE_SIGNATURE="$PRIMARY_SIGNATURE"
else
  ROLE_STATUS_AFTER="$(path_status "${SECONDARY_PATHS[@]}")"
  SESSION_META_AFTER="$(latest_session_meta_json "$OPENCLAW_HOME/agents/$SECONDARY_AGENT_ID/sessions/sessions.json" "$SESSION_ID_TO_USE")"
  ROLE_SIGNATURE="$SECONDARY_SIGNATURE"
fi

REPORT_JSON="$(parse_dispatch_report_json "$DISPATCH_OUTPUT")"
CHANGED_PATHS_JSON="$(status_diff_paths_json "$ROLE_STATUS_BEFORE" "$ROLE_STATUS_AFTER")"
HANDOFF_OUTPUT_FILE="$(write_handoff_file "$ROLE_TO_DISPATCH" "$NOW_ISO" "$SESSION_ID_TO_USE" "$REPORT_JSON")"
append_dispatch_history "$NOW_MS" "$NOW_ISO" "$ROLE_TO_DISPATCH" "$DISPATCH_EXIT_CODE" "$SESSION_ID_TO_USE" "$ROLLED_OVER" "$PROMPT" "$CHANGED_PATHS_JSON" "$REPORT_JSON" "$DISPATCH_OUTPUT"

REPORT_STATUS="$(json_field "$REPORT_JSON" status)"
REPORT_GOAL="$(json_field "$REPORT_JSON" goal)"
REPORT_CHANGED="$(json_field "$REPORT_JSON" changed)"
REPORT_VERIFIED="$(json_field "$REPORT_JSON" verified)"
REPORT_NEXT="$(json_field "$REPORT_JSON" next)"
REPORT_HANDOFF="$(json_field "$REPORT_JSON" handoff)"

SESSION_TOTAL_TOKENS_AFTER="$(json_field "$SESSION_META_AFTER" totalTokens)"
SESSION_CONTEXT_TOKENS_AFTER="$(json_field "$SESSION_META_AFTER" contextTokens)"
SESSION_UPDATED_AT_AFTER="$(json_field "$SESSION_META_AFTER" updatedAt)"

write_lane_json "$ROLE_TO_DISPATCH" "$NOW_MS" "$NOW_ISO" "$ROLE_SIGNATURE" "${REPORT_STATUS:-continue}" "${REPORT_GOAL:-}" "${REPORT_CHANGED:-}" "${REPORT_VERIFIED:-}" "${REPORT_NEXT:-}" "${REPORT_HANDOFF:-}" "$SESSION_ID_TO_USE" "${SESSION_TOTAL_TOKENS_AFTER:-0}" "${SESSION_CONTEXT_TOKENS_AFTER:-272000}" "${SESSION_UPDATED_AT_AFTER:-0}" "$ROLLOVER_COUNT" "$HANDOFF_OUTPUT_FILE"

if [ "$DISPATCH_EXIT_CODE" -eq 0 ]; then
  NEW_DISPATCH_COUNT=$((PREV_DISPATCH_COUNT + 1))
  write_state_json "$NOW_MS" "$NOW_ISO" "$PRIMARY_SIGNATURE" "$SECONDARY_SIGNATURE" "$PRIMARY_SESSION_UPDATED_AT" "$SECONDARY_SESSION_UPDATED_AT" "$PREV_LAST_ACTIVITY_AT" "$NOW_MS" "$ROLE_TO_DISPATCH" "$NEW_DISPATCH_COUNT" "dispatched" "Idle threshold reached; dispatched ${ROLE_TO_DISPATCH} agent (${REPORT_STATUS:-continue})"
  printf '[%s] dispatched %s agent (status=%s, rollover=%s)\n' "$NOW_ISO" "$ROLE_TO_DISPATCH" "${REPORT_STATUS:-continue}" "$ROLLED_OVER"
  printf '%s\n' "$DISPATCH_OUTPUT"
else
  write_state_json "$NOW_MS" "$NOW_ISO" "$PRIMARY_SIGNATURE" "$SECONDARY_SIGNATURE" "$PRIMARY_SESSION_UPDATED_AT" "$SECONDARY_SESSION_UPDATED_AT" "$PREV_LAST_ACTIVITY_AT" "$PREV_LAST_DISPATCH_AT" "$PREV_LAST_DISPATCHED_ROLE" "$PREV_DISPATCH_COUNT" "error" "Dispatch failed for ${ROLE_TO_DISPATCH} agent"
  printf '[%s] error: failed to dispatch %s agent\n' "$NOW_ISO" "$ROLE_TO_DISPATCH" >&2
  printf '%s\n' "$DISPATCH_OUTPUT" >&2
  exit "$DISPATCH_EXIT_CODE"
fi
