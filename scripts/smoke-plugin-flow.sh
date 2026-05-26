#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${KOREADER_NOTEBOOKLM_BRIDGE_URL:-http://127.0.0.1:8765}"

tmp_source="$(mktemp /tmp/koreader-notebooklm-source.XXXXXX.txt)"
trap 'rm -f "$tmp_source"' EXIT

cat > "$tmp_source" <<'TEXT'
This is a local smoke-test source for the KOReader NotebookLM bridge.
TEXT

echo "Creating notebook through $BASE_URL"
notebook_response="$(curl -fsS \
  -H 'Content-Type: application/json' \
  -d '{"title":"KOReader Smoke Notebook"}' \
  "$BASE_URL/notebooks")"
echo "$notebook_response"

notebook_id="$(python -c 'import json,sys; print(json.load(sys.stdin)["notebook"]["id"])' <<<"$notebook_response")"

echo "Uploading source to notebook=$notebook_id"
upload_response="$(curl -fsS \
  -F "notebook_id=$notebook_id" \
  -F "title=KOReader Smoke Source" \
  -F "wait=true" \
  -F "file=@$tmp_source" \
  "$BASE_URL/sources/upload-file")"
echo "$upload_response"

source_id="$(python -c 'import json,sys; print(json.load(sys.stdin)["source_id"])' <<<"$upload_response")"

echo "Linking smoke book to notebook"
curl -fsS \
  -H 'Content-Type: application/json' \
  -d "{\"book_id\":\"smoke-book\",\"notebook_id\":\"$notebook_id\",\"notebook_title\":\"KOReader Smoke Notebook\",\"title\":\"Smoke Book\",\"source_id\":\"$source_id\"}" \
  "$BASE_URL/books/link"
echo

echo "Fetching smoke book mapping"
curl -fsS "$BASE_URL/books/smoke-book"
echo

echo "Asking about highlighted text"
curl -fsS \
  -H 'Content-Type: application/json' \
  -d "{\"notebook_id\":\"$notebook_id\",\"selected_text\":\"Highlighted smoke passage.\",\"prompt\":\"Explain this simply.\",\"book\":{\"title\":\"Smoke Book\",\"position\":\"25%\"}}" \
  "$BASE_URL/ask"
echo
