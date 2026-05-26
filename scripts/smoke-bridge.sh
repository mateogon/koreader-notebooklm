#!/usr/bin/env sh
set -eu

BRIDGE_URL="${BRIDGE_URL:-http://127.0.0.1:8765}"

echo "Checking ${BRIDGE_URL}/health"
curl -fsS "${BRIDGE_URL}/health"
echo

echo "Checking ${BRIDGE_URL}/ask"
curl -fsS \
  -H "Content-Type: application/json" \
  -d '{"notebook_id":"mock-notebook","selected_text":"Smoke test passage.","prompt":"Explain this simply."}' \
  "${BRIDGE_URL}/ask"
echo
