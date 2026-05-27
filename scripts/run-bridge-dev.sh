#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/../bridge"

ADAPTER="${KOREADER_NOTEBOOKLM_ADAPTER:-mock}"
HOST="${KOREADER_NOTEBOOKLM_HOST:-127.0.0.1}"
PORT="${KOREADER_NOTEBOOKLM_PORT:-8765}"

echo "Starting bridge on http://${HOST}:${PORT} with adapter=${ADAPTER}"
if [ "$ADAPTER" = "mock" ]; then
  echo "Mock mode does not call NotebookLM, MCP, Google, or auth files."
elif [ "$ADAPTER" = "nlm-lite" ]; then
  echo "NLM Lite mode reads existing NotebookLM auth state and calls NotebookLM directly over HTTP."
else
  echo "Real mode delegates auth and NotebookLM access to the local nlm CLI."
fi
exec uv run uvicorn --app-dir src koreader_notebooklm_bridge.app:app --host "$HOST" --port "$PORT"
