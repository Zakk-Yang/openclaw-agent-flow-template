#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: bash scripts/openclaw/dispatch-agent.sh <agent-key> \"task\" [openclaw args...]" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_SCRIPT="$ROOT_DIR/scripts/openclaw/config.cjs"
AGENT_KEY="$1"
shift
USER_TASK="$1"
shift

if ! command -v openclaw >/dev/null 2>&1; then
  echo "openclaw is not installed or not on PATH" >&2
  exit 1
fi

PROJECT_NAME="$(node "$CONFIG_SCRIPT" project name)"
AGENT_ID="$(node "$CONFIG_SCRIPT" agent-id "$AGENT_KEY")"
ROLE_LABEL="$(node "$CONFIG_SCRIPT" agent "$AGENT_KEY" role_label)"
ROLE_FILE_REL="$(node "$CONFIG_SCRIPT" agent "$AGENT_KEY" role_file)"
ROLE_FILE="$ROOT_DIR/$ROLE_FILE_REL"

if [ ! -f "$ROLE_FILE" ]; then
  echo "Missing role brief: $ROLE_FILE" >&2
  exit 1
fi

ROLE_BRIEF="$(cat "$ROLE_FILE")"
PROMPT=$(cat <<EOF
You are the ${ROLE_LABEL} for the ${PROJECT_NAME} project.

Use the repo workspace at:
${ROOT_DIR}

Follow the repo instructions in AGENTS.md and this role brief.

<role_brief>
${ROLE_BRIEF}
</role_brief>

<user_task>
${USER_TASK}
</user_task>

When you finish, end with this exact compact report block:
STATUS: continue|done|blocked|defer
GOAL: one short sentence
CHANGED: one short sentence, or none
VERIFIED: one short sentence, or none
NEXT: one short sentence, or none
HANDOFF: one short sentence another fresh session could continue from

Keep each field brief and concrete.
EOF
)

exec openclaw agent --agent "$AGENT_ID" --message "$PROMPT" "$@"
