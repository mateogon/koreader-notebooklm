#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <koreader-plugins-dir> [--copy]"
  echo
  echo "Examples:"
  echo "  $0 /mnt/us/koreader/plugins --copy"
  echo "  $0 /path/to/koreader/plugins"
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$repo_root/plugin/notebooklm.koplugin"
plugins_dir="$1"
mode="${2:---symlink}"
target_dir="$plugins_dir/notebooklm.koplugin"

if [[ ! -d "$source_dir" ]]; then
  echo "Plugin source not found: $source_dir" >&2
  exit 1
fi

mkdir -p "$plugins_dir"

if [[ "$mode" == "--copy" ]]; then
  rm -rf "$target_dir"
  cp -R "$source_dir" "$target_dir"
  echo "Copied plugin to $target_dir"
elif [[ "$mode" == "--symlink" ]]; then
  rm -rf "$target_dir"
  ln -s "$source_dir" "$target_dir"
  echo "Symlinked plugin to $target_dir"
else
  echo "Unknown mode: $mode" >&2
  echo "Use --copy or omit the second argument for symlink mode." >&2
  exit 2
fi

echo "Restart KOReader after installing or updating the plugin."
