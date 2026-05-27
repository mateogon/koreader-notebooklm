#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${KOREADER_NOTEBOOKLM_BRIDGE_URL:-http://127.0.0.1:8765}"
SOURCE_FILE="${KOREADER_NOTEBOOKLM_SMOKE_FILE:-}"
NOTEBOOK_TITLE="${KOREADER_NOTEBOOKLM_SMOKE_NOTEBOOK_TITLE:-KOReader Bridge Flow Smoke $(date -u +%Y%m%dT%H%M%SZ)}"
BOOK_ID="${KOREADER_NOTEBOOKLM_SMOKE_BOOK_ID:-smoke-book-$(date -u +%Y%m%dT%H%M%SZ)}"
BOOK_TITLE="${KOREADER_NOTEBOOKLM_SMOKE_BOOK_TITLE:-KOReader Bridge Flow Smoke Book}"
ASK_TIMEOUT_SECONDS="${KOREADER_NOTEBOOKLM_SMOKE_ASK_TIMEOUT_SECONDS:-180}"
export BASE_URL NOTEBOOK_TITLE BOOK_ID BOOK_TITLE ASK_TIMEOUT_SECONDS

tmp_source=""
cleanup() {
  if [ -n "$tmp_source" ]; then
    rm -f "$tmp_source"
  fi
}
trap cleanup EXIT

json_field() {
  python3 -c 'import json,sys; data=json.load(sys.stdin); cur=data
for part in sys.argv[1].split("."):
    cur = cur[int(part)] if isinstance(cur, list) else cur[part]
print(cur)' "$1"
}

assert_json_expr() {
  python3 -c 'import json,sys; body=json.load(sys.stdin); expr=sys.argv[1]; assert eval(expr, {"body": body}), body' "$1"
}

if [ -z "$SOURCE_FILE" ]; then
  tmp_source="$(mktemp /tmp/koreader-notebooklm-bridge-flow.XXXXXX).md"
  SOURCE_FILE="$tmp_source"
  cat > "$SOURCE_FILE" <<'TEXT'
# KOReader Bridge Flow Smoke

This source exists only to validate the local bridge flow that KOReader uses.
The bridge should upload this file, link it to a book, and answer a question
about the phrase "bridge flow smoke".
TEXT
fi

if [ ! -f "$SOURCE_FILE" ]; then
  echo "Source file does not exist: $SOURCE_FILE" >&2
  exit 1
fi
export SOURCE_FILE

echo "Bridge flow smoke"
echo "  base_url: $BASE_URL"
echo "  source:   $SOURCE_FILE"
echo "  title:    $NOTEBOOK_TITLE"
echo "  book_id:  $BOOK_ID"
echo

echo "1. GET /health"
health_response="$(curl -fsS "$BASE_URL/health")"
echo "$health_response"
adapter="$(printf '%s' "$health_response" | json_field "adapter")"
printf '%s' "$health_response" | assert_json_expr 'body["ok"] is True'
echo "   adapter=$adapter"
echo

echo "2. POST /notebooks"
notebook_response="$(curl -fsS \
  -H "Content-Type: application/json" \
  -d "$(python3 -c 'import json,os; print(json.dumps({"title": os.environ["NOTEBOOK_TITLE"]}))')" \
  "$BASE_URL/notebooks")"
echo "$notebook_response"
notebook_id="$(printf '%s' "$notebook_response" | json_field "notebook.id")"
printf '%s' "$notebook_response" | assert_json_expr 'body["ok"] is True and body["notebook"]["id"]'
echo "   notebook_id=$notebook_id"
echo

echo "3. POST /sources/upload-file"
upload_response="$(curl -fsS \
  -F "notebook_id=$notebook_id" \
  -F "title=$(basename "$SOURCE_FILE")" \
  -F "wait=true" \
  -F "file=@$SOURCE_FILE" \
  "$BASE_URL/sources/upload-file")"
echo "$upload_response"
source_id="$(printf '%s' "$upload_response" | json_field "source_id")"
printf '%s' "$upload_response" | assert_json_expr 'body["ok"] is True and body["source_id"]'
echo "   source_id=$source_id"
echo

echo "4. POST /books/link"
link_payload="$(
  NOTEBOOK_ID="$notebook_id" SOURCE_ID="$source_id" python3 - <<'PY'
import json
import os

print(json.dumps({
    "book_id": os.environ["BOOK_ID"],
    "notebook_id": os.environ["NOTEBOOK_ID"],
    "notebook_title": os.environ["NOTEBOOK_TITLE"],
    "title": os.environ["BOOK_TITLE"],
    "path": os.environ["SOURCE_FILE"],
    "source_id": os.environ["SOURCE_ID"],
}, separators=(",", ":")))
PY
)"
link_response="$(curl -fsS \
  -H "Content-Type: application/json" \
  -d "$link_payload" \
  "$BASE_URL/books/link")"
echo "$link_response"
printf '%s' "$link_response" | assert_json_expr 'body["ok"] is True and body["book"]["source_id"]'
echo

echo "5. GET /books/$BOOK_ID"
book_response="$(curl -fsS "$BASE_URL/books/$BOOK_ID")"
echo "$book_response"
printf '%s' "$book_response" | assert_json_expr 'body["ok"] is True and body["book"]["notebook_id"]'
echo

echo "6. POST /ask/jobs"
ask_payload="$(
  NOTEBOOK_ID="$notebook_id" python3 - <<'PY'
import json
import os

print(json.dumps({
    "notebook_id": os.environ["NOTEBOOK_ID"],
    "selected_text": "bridge flow smoke",
    "prompt": "Explain this selected phrase in one concise sentence.",
    "book": {
        "title": os.environ["BOOK_TITLE"],
        "path": os.environ["SOURCE_FILE"],
        "position": "smoke-test",
    },
}, separators=(",", ":")))
PY
)"
job_response="$(curl -fsS \
  -H "Content-Type: application/json" \
  -d "$ask_payload" \
  "$BASE_URL/ask/jobs")"
echo "$job_response"
job_id="$(printf '%s' "$job_response" | json_field "job_id")"
printf '%s' "$job_response" | assert_json_expr 'body["ok"] is True and body["job_id"]'
echo "   job_id=$job_id"
echo

echo "7. GET /ask/jobs/$job_id until complete"
deadline=$((SECONDS + ASK_TIMEOUT_SECONDS))
while :; do
  poll_response="$(curl -fsS "$BASE_URL/ask/jobs/$job_id")"
  status="$(printf '%s' "$poll_response" | json_field "status")"
  echo "   status=$status"

  if [ "$status" = "succeeded" ]; then
    echo "$poll_response"
    printf '%s' "$poll_response" | assert_json_expr 'body["ok"] is True and body["result"]["answer"].strip()'
    echo
    echo "bridge-flow=ok"
    exit 0
  fi

  if [ "$status" = "failed" ]; then
    echo "$poll_response" >&2
    exit 1
  fi

  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "Timed out waiting for ask job $job_id after ${ASK_TIMEOUT_SECONDS}s" >&2
    echo "$poll_response" >&2
    exit 1
  fi

  sleep 2
done
