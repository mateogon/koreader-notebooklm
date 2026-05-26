#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugins_dir="${1:-}"
bridge_url="${2:-${KOREADER_NOTEBOOKLM_BRIDGE_URL:-http://127.0.0.1:8765}}"

plugin_name="notebooklm.koplugin"
source_dir="$repo_root/plugin/$plugin_name"

echo "KOReader NotebookLM runtime preflight"
echo

if [[ ! -d "$source_dir" ]]; then
  echo "FAIL: plugin source not found: $source_dir" >&2
  exit 1
fi

echo "Local plugin source: $source_dir"
for file in _meta.lua main.lua client.lua http.lua ui.lua settings.lua storage.lua prompts.lua; do
  if [[ ! -f "$source_dir/$file" ]]; then
    echo "FAIL: missing plugin source file: $file" >&2
    exit 1
  fi
done
echo "OK: required plugin source files exist"

if [[ -n "$plugins_dir" ]]; then
  target_dir="$plugins_dir/$plugin_name"
  echo
  echo "KOReader plugins dir: $plugins_dir"
  if [[ ! -d "$plugins_dir" ]]; then
    echo "WARN: plugins dir does not exist yet"
  elif [[ ! -e "$target_dir" ]]; then
    echo "WARN: plugin is not installed at $target_dir"
    echo "      install with: scripts/install-plugin-dev.sh \"$plugins_dir\" --copy"
  else
    echo "OK: plugin install target exists: $target_dir"
    for file in _meta.lua main.lua client.lua http.lua ui.lua settings.lua storage.lua prompts.lua; do
      if [[ ! -f "$target_dir/$file" ]]; then
        echo "FAIL: installed plugin is missing: $file" >&2
        exit 1
      fi
    done
    echo "OK: installed plugin has required files"
  fi

  koreader_root="$(cd "$plugins_dir/.." 2>/dev/null && pwd || true)"
  if [[ -n "$koreader_root" ]]; then
    echo
    echo "KOReader log candidates:"
    find "$koreader_root" -maxdepth 2 \( -name 'crash.log' -o -name '*.log' \) -print 2>/dev/null | sort | tail -20 || true
  fi
else
  echo
  echo "No KOReader plugins dir was provided; skipping installed-plugin checks."
  echo "Usage: $0 /path/to/koreader/plugins [bridge-url]"
fi

echo
echo "Bridge health: $bridge_url/health"
if command -v curl >/dev/null 2>&1; then
  if curl -fsS --max-time 2 "$bridge_url/health" >/tmp/koreader-notebooklm-preflight-health.json 2>/tmp/koreader-notebooklm-preflight-health.err; then
    echo "OK: bridge responded"
    cat /tmp/koreader-notebooklm-preflight-health.json
    echo
  else
    echo "WARN: bridge health check failed"
    sed 's/^/      /' /tmp/koreader-notebooklm-preflight-health.err || true
  fi
  rm -f /tmp/koreader-notebooklm-preflight-health.json /tmp/koreader-notebooklm-preflight-health.err
else
  echo "WARN: curl not found; bridge health was not checked"
fi

echo
echo "Manual KOReader acceptance still required:"
echo "1. Restart KOReader after installing the plugin."
echo "2. Open a book and check NotebookLM -> Status."
echo "3. Link or create a notebook from NotebookLM -> Current book setup."
echo "4. Highlight text and run Ask NotebookLM plus one preset prompt."
echo "5. Confirm the answer opens and KOReader logs show no Lua stack trace."
