#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_SCRIPT="$ROOT_DIR/scripts/openclaw/config.cjs"
PROJECT_SLUG="$(node "$CONFIG_SCRIPT" project slug)"

require_openclaw() {
  if ! command -v openclaw >/dev/null 2>&1; then
    echo "openclaw is not installed or not on PATH" >&2
    exit 1
  fi
}

agent_exists() {
  local agent_id="$1"
  openclaw agents list | grep -Fq -- "- ${agent_id}"
}

register_agent() {
  local key="$1"
  local agent_id
  local identity_name

  agent_id="$(node "$CONFIG_SCRIPT" agent-id "$key")"
  identity_name="$(node "$CONFIG_SCRIPT" agent "$key" identity_name)"

  if agent_exists "$agent_id"; then
    printf 'Agent exists: %s\n' "$agent_id"
  else
    openclaw agents add "$agent_id" --non-interactive --workspace "$ROOT_DIR" >/dev/null
    printf 'Agent added: %s\n' "$agent_id"
  fi

  openclaw agents set-identity --agent "$agent_id" --name "$identity_name" >/dev/null
  printf 'Agent ready: %s (%s)\n' "$agent_id" "$identity_name"
}

require_openclaw

printf 'Workspace: %s\n' "$ROOT_DIR"
printf 'Project slug: %s\n' "$PROJECT_SLUG"

while IFS= read -r key; do
  [ -n "$key" ] || continue
  register_agent "$key"
done < <(node "$CONFIG_SCRIPT" agent-keys)

printf '\nDispatch commands:\n'
printf '  bash scripts/openclaw/dispatch-primary.sh "your task"\n'
printf '  bash scripts/openclaw/dispatch-secondary.sh "your task"\n'
