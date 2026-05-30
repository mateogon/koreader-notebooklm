#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PLUGIN_SRC="$REPO_ROOT/plugin/notebooklm.koplugin"
DIST_DIR="$REPO_ROOT/dist"

usage() {
  cat <<'USAGE'
Usage:
  scripts/package-plugin.sh [--version <name>] [--output-dir <dir>]

Creates an installable KOReader plugin zip:
  dist/notebooklm.koplugin-<version>.zip

The zip root is notebooklm.koplugin/, ready to extract into:
  /mnt/us/koreader/plugins/
USAGE
}

VERSION=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      [ "$#" -ge 2 ] || { echo "error: --version requires a value" >&2; exit 2; }
      VERSION="$2"
      shift 2
      ;;
    --output-dir)
      [ "$#" -ge 2 ] || { echo "error: --output-dir requires a value" >&2; exit 2; }
      DIST_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

[ -d "$PLUGIN_SRC" ] || { echo "error: plugin source not found: $PLUGIN_SRC" >&2; exit 1; }
command -v zip >/dev/null 2>&1 || { echo "error: zip is required" >&2; exit 1; }

if [ -z "$VERSION" ]; then
  short_sha="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
  if [ -n "$short_sha" ]; then
    VERSION="alpha-$(date -u +%Y%m%d)-$short_sha"
  else
    VERSION="alpha-$(date -u +%Y%m%d)"
  fi
fi

mkdir -p "$DIST_DIR"
tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

cp -R "$PLUGIN_SRC" "$tmp_dir/notebooklm.koplugin"

find "$tmp_dir/notebooklm.koplugin" \
  \( -name '.DS_Store' -o -name '*.swp' -o -name '*.tmp' -o -name '*.log' \) \
  -delete

artifact="$DIST_DIR/notebooklm.koplugin-$VERSION.zip"
rm -f "$artifact"

(
  cd "$tmp_dir"
  zip -qr "$artifact" notebooklm.koplugin
)

echo "Created $artifact"
echo "Install by extracting notebooklm.koplugin/ into KOReader's plugins directory."
