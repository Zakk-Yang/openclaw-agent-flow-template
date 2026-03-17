#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_TEMPLATE_SOURCE="${OPENCLAW_FLOW_TEMPLATE_SOURCE:-$TEMPLATE_ROOT}"
DEFAULT_PARENT_DIR="${OPENCLAW_FLOW_PARENT_DIR:-$HOME/projects/_active}"

usage() {
  cat <<'EOF'
Usage:
  new-agent-flow <project-slug> [target-dir] [--name "Project Name"] [--template <path-or-git-url>]

Examples:
  new-agent-flow market-watch
  new-agent-flow market-watch "$HOME/projects/_active/market-watch"
  new-agent-flow market-watch --name "Market Watch"

Behavior:
  - copies or clones the OpenClaw agent-flow template
  - rewrites the project slug, name, and tmux session in .openclaw/project.json
  - removes the template git history
  - initializes a fresh git repo on main
  - creates an initial scaffold commit when git identity is configured
EOF
}

title_case() {
  node -e '
    const input = process.argv[1];
    const value = input
      .split(/[-_]+/)
      .filter(Boolean)
      .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
      .join(" ");
    process.stdout.write(value || input);
  ' "$1"
}

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

PROJECT_SLUG="$1"
shift

TARGET_DIR=""
PROJECT_NAME=""
TEMPLATE_SOURCE="$DEFAULT_TEMPLATE_SOURCE"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --template)
      TEMPLATE_SOURCE="$2"
      shift 2
      ;;
    *)
      if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [ -z "$TARGET_DIR" ]; then
  TARGET_DIR="$DEFAULT_PARENT_DIR/$PROJECT_SLUG"
fi

if [ -z "$PROJECT_NAME" ]; then
  PROJECT_NAME="$(title_case "$PROJECT_SLUG")"
fi

if [ -e "$TARGET_DIR" ]; then
  echo "Target already exists: $TARGET_DIR" >&2
  exit 1
fi

mkdir -p "$(dirname "$TARGET_DIR")"

if [ -d "$TEMPLATE_SOURCE/.git" ] || [ -f "$TEMPLATE_SOURCE/README.md" ]; then
  cp -a "$TEMPLATE_SOURCE" "$TARGET_DIR"
else
  git clone --depth 1 "$TEMPLATE_SOURCE" "$TARGET_DIR" >/dev/null
fi

rm -rf "$TARGET_DIR/.git" "$TARGET_DIR/.openclaw/runtime"

node -e '
  const fs = require("fs");
  const path = process.argv[1];
  const slug = process.argv[2];
  const name = process.argv[3];
  const payload = JSON.parse(fs.readFileSync(path, "utf8"));
  payload.project.slug = slug;
  payload.project.name = name;
  payload.project.tmux_session = `${slug}-heartbeat`;
  for (const agent of payload.agents || []) {
    agent.identity_name = `${name} ${agent.key === "primary" ? "Primary" : "Secondary"} Agent`;
  }
  fs.writeFileSync(path, JSON.stringify(payload, null, 2) + "\n", "utf8");
  ' "$TARGET_DIR/.openclaw/project.json" "$PROJECT_SLUG" "$PROJECT_NAME"

if git init -b main "$TARGET_DIR" >/dev/null 2>&1; then
  :
else
  git init "$TARGET_DIR" >/dev/null
  git -C "$TARGET_DIR" branch -m main >/dev/null 2>&1 || true
fi

if git -C "$TARGET_DIR" add . >/dev/null 2>&1 && git -C "$TARGET_DIR" commit -m "Initial template scaffold" >/dev/null 2>&1; then
  INITIAL_COMMIT_CREATED="yes"
else
  INITIAL_COMMIT_CREATED="no"
fi

cat <<EOF
Created project:
  $TARGET_DIR

Updated defaults:
  slug: $PROJECT_SLUG
  name: $PROJECT_NAME
  template source: $TEMPLATE_SOURCE
  initial commit created: $INITIAL_COMMIT_CREATED

Next steps:
  cd "$TARGET_DIR"
  edit AGENTS.md
  edit .openclaw/project.json
  edit .openclaw/roles/agent-a.md
  edit .openclaw/roles/agent-b.md
  bash scripts/openclaw/setup-project-agents.sh
  bash scripts/openclaw/start-supervisor-tmux.sh
EOF
