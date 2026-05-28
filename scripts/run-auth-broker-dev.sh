#!/usr/bin/env sh
set -eu

HOST="${KOREADER_NOTEBOOKLM_HOST:-127.0.0.1}"
PORT="${KOREADER_NOTEBOOKLM_PORT:-8767}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if [ "$HOST" = "0.0.0.0" ]; then
  echo "WARNING: auth broker is LAN-exposed. Use only on a trusted network."
fi

echo "Starting auth broker on http://${HOST}:${PORT}"
echo "Auth bundles are temporary credentials and are written outside the repo."

exec uv run --project "$REPO_ROOT/bridge" uvicorn \
  --app-dir "$REPO_ROOT/bridge/src" \
  koreader_notebooklm_bridge.app:app \
  --host "$HOST" \
  --port "$PORT"
