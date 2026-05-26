#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

work_dir="${KOREADER_MACOS_SMOKE_DIR:-/tmp/koreader-notebooklm-macos}"
run_id="${KOREADER_MACOS_RUN_ID:-23214193860}"
artifact_id="${KOREADER_MACOS_ARTIFACT_ID:-5973069038}"
artifact_name="${KOREADER_MACOS_ARTIFACT_NAME:-KOReader-arm64-2026.03.7z}"
bridge_url="${KOREADER_NOTEBOOKLM_BRIDGE_URL:-http://127.0.0.1:8765}"
timeout_seconds="${KOREADER_MACOS_SMOKE_TIMEOUT:-8}"

archive_path="$work_dir/$artifact_name"
extract_dir="$work_dir/extracted"
app_dir="$extract_dir/KOReader.app"
plugins_dir="$app_dir/Contents/koreader/plugins"
exe="$app_dir/Contents/MacOS/koreader"
epub_path="$work_dir/koreader-runtime-smoke.epub"
runtime_log="$work_dir/runtime-smoke.log"
bridge_log="$work_dir/bridge-smoke.log"
bridge_pid=""

cleanup() {
  if [[ -n "$bridge_pid" ]]; then
    kill "$bridge_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need_cmd bsdtar
need_cmd curl
need_cmd python

mkdir -p "$work_dir"

if [[ ! -f "$archive_path" ]]; then
  need_cmd gh
  echo "Downloading KOReader macOS artifact $artifact_name"
  # GitHub returns this artifact as a .7z payload, despite the API path ending in /zip.
  gh api "repos/koreader/koreader/actions/artifacts/$artifact_id/zip" > "$archive_path.tmp"
  mv "$archive_path.tmp" "$archive_path"
fi

if [[ ! -d "$app_dir" ]]; then
  echo "Extracting $archive_path"
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  bsdtar -xf "$archive_path" -C "$extract_dir"
fi

if [[ ! -x "$exe" ]]; then
  echo "KOReader executable not found: $exe" >&2
  exit 1
fi

"$repo_root/scripts/install-plugin-dev.sh" "$plugins_dir" --copy

python - "$epub_path" <<'PY'
from pathlib import Path
import sys
import zipfile

epub = Path(sys.argv[1])
epub.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(epub, "w") as z:
    z.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
    z.writestr(
        "META-INF/container.xml",
        """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
""",
    )
    z.writestr(
        "OEBPS/content.opf",
        """<?xml version="1.0" encoding="utf-8"?>
<package version="3.0" unique-identifier="bookid" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">koreader-notebooklm-runtime-smoke</dc:identifier>
    <dc:title>KOReader NotebookLM Runtime Smoke</dc:title>
    <dc:language>en</dc:language>
  </metadata>
  <manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest>
  <spine><itemref idref="chapter"/></spine>
</package>
""",
    )
    z.writestr(
        "OEBPS/chapter.xhtml",
        """<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Runtime Smoke</title></head>
  <body>
    <h1>Runtime Smoke</h1>
    <p>KOReader NotebookLM plugin runtime smoke.</p>
  </body>
</html>
""",
    )
PY

if ! curl -fsS --max-time 2 "$bridge_url/health" >/dev/null 2>&1; then
  echo "Starting mock bridge for runtime smoke"
  (
    cd "$repo_root"
    KOREADER_NOTEBOOKLM_ADAPTER=mock \
      KOREADER_NOTEBOOKLM_HOST=127.0.0.1 \
      KOREADER_NOTEBOOKLM_PORT=8765 \
      scripts/run-bridge-dev.sh
  ) >"$bridge_log" 2>&1 &
  bridge_pid="$!"

  for _ in $(seq 1 30); do
    if curl -fsS --max-time 1 "$bridge_url/health" >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done
fi

"$repo_root/scripts/koreader-runtime-preflight.sh" "$plugins_dir" "$bridge_url"

echo "Launching KOReader macOS runtime smoke for ${timeout_seconds}s"
python - "$exe" "$epub_path" "$runtime_log" "$timeout_seconds" <<'PY'
import subprocess
import sys
from pathlib import Path

exe, epub, log_path, timeout = sys.argv[1], sys.argv[2], Path(sys.argv[3]), float(sys.argv[4])
try:
    completed = subprocess.run(
        [exe, "-d", epub],
        cwd=str(Path(exe).parents[1] / "koreader"),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    output = completed.stdout
    status = f"EXIT_CODE {completed.returncode}"
except subprocess.TimeoutExpired as e:
    output = e.stdout or ""
    if isinstance(output, bytes):
        output = output.decode(errors="replace")
    status = f"TIMEOUT_AFTER_SECONDS {e.timeout}"
log_path.write_text(status + "\n" + output)
print(status)
print(log_path)
PY

if ! grep -q "Plugin loaded notebooklm" "$runtime_log"; then
  echo "KOReader did not log plugin load for notebooklm" >&2
  tail -120 "$runtime_log" >&2
  exit 1
fi

if ! grep -q "RD loaded plugin notebooklm" "$runtime_log"; then
  echo "KOReader did not register notebooklm in ReaderUI logs" >&2
  tail -120 "$runtime_log" >&2
  exit 1
fi

if grep -q "stack traceback" "$runtime_log"; then
  echo "KOReader runtime smoke found a Lua stack traceback" >&2
  grep -n -C 8 "stack traceback" "$runtime_log" >&2
  exit 1
fi

echo "KOReader macOS runtime smoke ok"
echo "Log: $runtime_log"
