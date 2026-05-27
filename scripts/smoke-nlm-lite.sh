#!/usr/bin/env sh
set -eu

BASE_URL="${KOREADER_NOTEBOOKLM_BRIDGE_URL:-http://127.0.0.1:8765}"

echo "Checking ${BASE_URL}/health"
health="$(curl -fsS "${BASE_URL}/health")"
echo "$health"
echo "$health" | python -c 'import json,sys; body=json.load(sys.stdin); assert body["adapter"] == "nlm-lite", body'

echo
echo "Checking ${BASE_URL}/notebooks through nlm-lite"
notebooks="$(curl -fsS "${BASE_URL}/notebooks")"
echo "$notebooks" | python -c 'import json,sys; body=json.load(sys.stdin); assert body["ok"] is True; assert isinstance(body["notebooks"], list); print("notebooks={}".format(len(body["notebooks"])))'

if [ -n "${KOREADER_NOTEBOOKLM_DEFAULT_NOTEBOOK_ID:-}" ]; then
  echo
  echo "Checking ${BASE_URL}/ask through nlm-lite with default notebook"
  curl -fsS \
    -H "Content-Type: application/json" \
    -d '{"selected_text":"KOReader NotebookLM nlm-lite smoke.","prompt":"Reply with one short sentence about this phrase."}' \
    "${BASE_URL}/ask" |
    python -c 'import json,sys; body=json.load(sys.stdin); assert body["ok"] is True; assert body["adapter"] == "nlm-lite"; assert body["answer"].strip(); print("ask=ok")'
else
  echo
  echo "Skipping /ask smoke because KOREADER_NOTEBOOKLM_DEFAULT_NOTEBOOK_ID is not set."
fi
