#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v openclaw >/dev/null 2>&1; then
  echo "openclaw is not installed or not on PATH" >&2
  exit 1
fi

exec node "$ROOT_DIR/scripts/openclaw/session-costs.cjs" "$@"
