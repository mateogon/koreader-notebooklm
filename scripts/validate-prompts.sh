#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CONFIG_PATH="${1:-}"

if [ -z "$CONFIG_PATH" ] || [ "$CONFIG_PATH" = "-h" ] || [ "$CONFIG_PATH" = "--help" ]; then
  cat <<'USAGE'
Usage:
  scripts/validate-prompts.sh <notebooklm-prompts.lua>

Validates a KOReader NotebookLM prompt config before syncing it to Kindle.
USAGE
  [ -n "$CONFIG_PATH" ] && exit 0 || exit 2
fi

if [ ! -f "$CONFIG_PATH" ]; then
  echo "error: prompt config does not exist: $CONFIG_PATH" >&2
  exit 1
fi

find_lua() {
  if [ -n "${KOREADER_LUAJIT:-}" ]; then
    printf '%s\n' "$KOREADER_LUAJIT"
    return 0
  fi
  for candidate in \
    "/Applications/KOReader.app/Contents/koreader/luajit" \
    "/tmp/koreader-notebooklm-macos/extracted/KOReader.app/Contents/koreader/luajit"
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  if command -v luajit >/dev/null 2>&1; then
    command -v luajit
    return 0
  fi
  if command -v lua >/dev/null 2>&1; then
    command -v lua
    return 0
  fi
  return 1
}

LUA_BIN="$(find_lua)" || {
  echo "error: could not find Lua. Set KOREADER_LUAJIT=/path/to/luajit." >&2
  exit 1
}

exec "$LUA_BIN" "$SCRIPT_DIR/validate-prompts.lua" "$CONFIG_PATH"
