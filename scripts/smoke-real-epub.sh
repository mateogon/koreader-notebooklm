#!/usr/bin/env bash
set -euo pipefail

if [[ "${KOREADER_NOTEBOOKLM_REAL_SMOKE:-}" != "1" ]]; then
  echo "This smoke test calls the real nlm/NotebookLM path." >&2
  echo "Set KOREADER_NOTEBOOKLM_REAL_SMOKE=1 to run it intentionally." >&2
  exit 2
fi

BASE_URL="${KOREADER_NOTEBOOKLM_BRIDGE_URL:-http://127.0.0.1:8765}"
TITLE="KOReader EPUB Smoke $(date -u +%Y-%m-%dT%H:%M:%SZ)"
tmp_dir="$(mktemp -d /tmp/koreader-notebooklm-real.XXXXXX)"
epub_path="$tmp_dir/koreader-smoke.epub"
notebook_id=""

cleanup() {
  rm -rf "$tmp_dir"
  if [[ -n "$notebook_id" && "${KEEP_REAL_SMOKE_NOTEBOOK:-}" != "1" ]]; then
    echo "Deleting temporary notebook $notebook_id"
    nlm notebook delete "$notebook_id" --confirm >/dev/null || true
  fi
}
trap cleanup EXIT

python - "$epub_path" <<'PY'
from pathlib import Path
import sys
import zipfile

epub = Path(sys.argv[1])
with zipfile.ZipFile(epub, "w") as z:
    z.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
    z.writestr(
        "META-INF/container.xml",
        """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
""",
    )
    z.writestr(
        "OEBPS/content.opf",
        """<?xml version="1.0" encoding="utf-8"?>
<package version="3.0" unique-identifier="bookid" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">koreader-notebooklm-smoke</dc:identifier>
    <dc:title>KOReader NotebookLM Smoke EPUB</dc:title>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chapter"/>
  </spine>
</package>
""",
    )
    z.writestr(
        "OEBPS/nav.xhtml",
        """<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Navigation</title></head>
  <body><nav epub:type="toc"><ol><li><a href="chapter.xhtml">Smoke</a></li></ol></nav></body>
</html>
""",
    )
    z.writestr(
        "OEBPS/chapter.xhtml",
        """<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Smoke</title></head>
  <body>
    <h1>KOReader NotebookLM Smoke EPUB</h1>
    <p>The bridge can upload an EPUB source and ask NotebookLM about highlighted text.</p>
    <p>The phrase alpha bridge passage is used as a deterministic query target.</p>
  </body>
</html>
""",
    )
PY

echo "Checking bridge health at $BASE_URL"
curl -fsS "$BASE_URL/health"
echo

echo "Creating temporary notebook"
create_response="$(curl -fsS \
  -H 'Content-Type: application/json' \
  -d "{\"title\":\"$TITLE\"}" \
  "$BASE_URL/notebooks")"
echo "$create_response"
notebook_id="$(python -c 'import json,sys; print(json.load(sys.stdin)["notebook"]["id"])' <<<"$create_response")"

echo "Uploading EPUB source"
curl -fsS \
  -F "notebook_id=$notebook_id" \
  -F "title=KOReader Smoke EPUB" \
  -F "wait=true" \
  -F "file=@$epub_path;type=application/epub+zip" \
  "$BASE_URL/sources/upload-file"
echo

echo "Asking NotebookLM about uploaded EPUB"
curl -fsS \
  -H 'Content-Type: application/json' \
  -d "{\"notebook_id\":\"$notebook_id\",\"selected_text\":\"alpha bridge passage\",\"prompt\":\"Explain this phrase using only the uploaded EPUB source.\",\"book\":{\"title\":\"KOReader NotebookLM Smoke EPUB\",\"position\":\"smoke\"}}" \
  "$BASE_URL/ask"
echo
