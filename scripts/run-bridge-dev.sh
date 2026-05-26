#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/../bridge"

ADAPTER="${KOREADER_NOTEBOOKLM_ADAPTER:-mock}"

echo "Starting bridge on http://127.0.0.1:8765 with adapter=${ADAPTER}"
if [ "$ADAPTER" = "mock" ]; then
  echo "Mock mode does not call NotebookLM, MCP, Google, or auth files."
else
  echo "Real mode delegates auth and NotebookLM access to the local nlm CLI."
fi
exec uv run uvicorn --app-dir src koreader_notebooklm_bridge.app:app --host 127.0.0.1 --port 8765
