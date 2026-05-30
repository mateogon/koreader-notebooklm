#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

SOURCE=""
USB_MOUNT=""
SSH_HOST=""
SSH_PORT="2222"
DRY_RUN="0"
REMOTE_PATH="/mnt/us/koreader/settings/notebooklm-prompts.lua"

usage() {
  cat <<'USAGE'
Usage:
  scripts/sync-prompts-to-kindle.sh --file ~/notebooklm-prompts.lua --usb /Volumes/Kindle
  scripts/sync-prompts-to-kindle.sh --file ~/notebooklm-prompts.lua --ssh 192.168.0.105 --port 2222

Options:
  --file <path>       Prompt config to validate and sync.
  --usb <mount-path>  Kindle USB mount path.
  --ssh <host>        Kindle SSH host/IP. Uses root@host unless user@host is given.
  --port <port>       SSH port, default 2222.
  --dry-run           Print actions without copying.
  -h, --help          Show this help.

Destination:
  koreader/settings/notebooklm-prompts.lua
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf 'dry-run:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --file)
      [ "$#" -ge 2 ] || die "--file requires a path"
      SOURCE="$2"
      shift 2
      ;;
    --usb)
      [ "$#" -ge 2 ] || die "--usb requires a mount path"
      USB_MOUNT="$2"
      shift 2
      ;;
    --ssh)
      [ "$#" -ge 2 ] || die "--ssh requires a host"
      SSH_HOST="$2"
      shift 2
      ;;
    --port)
      [ "$#" -ge 2 ] || die "--port requires a value"
      SSH_PORT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[ -n "$SOURCE" ] || {
  usage
  die "missing --file"
}
[ -f "$SOURCE" ] || die "prompt config does not exist: $SOURCE"

if [ -n "$USB_MOUNT" ] && [ -n "$SSH_HOST" ]; then
  die "choose exactly one destination: --usb or --ssh"
fi
if [ -z "$USB_MOUNT" ] && [ -z "$SSH_HOST" ]; then
  usage
  die "missing destination: pass --usb or --ssh"
fi

"$SCRIPT_DIR/validate-prompts.sh" "$SOURCE"

if [ -n "$USB_MOUNT" ]; then
  SETTINGS_DIR="${USB_MOUNT%/}/koreader/settings"
  TARGET="$SETTINGS_DIR/notebooklm-prompts.lua"
  [ -d "$USB_MOUNT" ] || die "USB mount does not exist: $USB_MOUNT"
  echo "Syncing prompt config over USB."
  echo "  destination: $TARGET"
  run mkdir -p "$SETTINGS_DIR"
  run cp "$SOURCE" "$TARGET"
  run chmod 600 "$TARGET" 2>/dev/null || true
else
  case "$SSH_HOST" in
    *@*) SSH_TARGET="$SSH_HOST" ;;
    *) SSH_TARGET="root@$SSH_HOST" ;;
  esac
  SSH_OPTS=(-p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=2 -o ServerAliveCountMax=2)
  SCP_OPTS=(-P "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=2 -o ServerAliveCountMax=2)
  echo "Syncing prompt config over SSH."
  echo "  destination: ${SSH_TARGET}:${REMOTE_PATH}"
  run ssh "${SSH_OPTS[@]}" "$SSH_TARGET" 'mkdir -p /mnt/us/koreader/settings'
  run scp "${SCP_OPTS[@]}" "$SOURCE" "${SSH_TARGET}:${REMOTE_PATH}"
  run ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "chmod 600 '$REMOTE_PATH' 2>/dev/null || true"
fi

echo ""
echo "Prompt sync complete. Restart KOReader to force a clean plugin reload."
