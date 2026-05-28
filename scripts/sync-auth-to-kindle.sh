#!/usr/bin/env bash
set -euo pipefail

# Generate or reuse a local nlm-lite auth bundle and copy it to KOReader on Kindle.
# The auth bundle contains NotebookLM cookies/tokens. Treat it like a password.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

PROFILE="default"
LOCAL_BUNDLE=""
USB_MOUNT=""
SSH_HOST=""
SSH_PORT="2222"
REFRESH="0"
CONFIGURE="1"
SMOKE="1"
DRY_RUN="0"
DIRECT_NOTEBOOK_ID=""
REMOTE_BUNDLE="/mnt/us/koreader/settings/notebooklm-auth-bundle.json"

usage() {
  cat <<'USAGE'
Usage:
  scripts/sync-auth-to-kindle.sh --usb /Volumes/Kindle
  scripts/sync-auth-to-kindle.sh --ssh 192.168.0.105 --port 2222

Options:
  --usb <mount-path>       Kindle USB mount path.
  --ssh <host>             Kindle SSH host/IP.
  --port <port>            SSH port, default 2222.
  --profile <name>         Local auth profile, default default.
  --bundle <path>          Reuse or write a specific local auth bundle path.
  --refresh                Force Chrome login and overwrite the local bundle.
  --notebook-id <id>       Optional lua-direct default notebook id.
  --no-configure           Copy bundle only; do not write notebooklm.lua.
  --no-smoke               Skip post-sync smoke guidance.
  --dry-run                Print actions without writing or opening Chrome.
  -h, --help               Show this help.

Notes:
  USB mode is easiest for non-technical users, but Kindle must be mounted as USB storage.
  SSH mode is faster for development, but Kindle must be awake with SSH enabled.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

log() {
  echo "$*"
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
    --profile)
      [ "$#" -ge 2 ] || die "--profile requires a name"
      PROFILE="$2"
      shift 2
      ;;
    --bundle)
      [ "$#" -ge 2 ] || die "--bundle requires a path"
      LOCAL_BUNDLE="$2"
      shift 2
      ;;
    --refresh)
      REFRESH="1"
      shift
      ;;
    --notebook-id)
      [ "$#" -ge 2 ] || die "--notebook-id requires an id"
      DIRECT_NOTEBOOK_ID="$2"
      shift 2
      ;;
    --no-configure)
      CONFIGURE="0"
      shift
      ;;
    --no-smoke)
      SMOKE="0"
      shift
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

if [ -n "$USB_MOUNT" ] && [ -n "$SSH_HOST" ]; then
  die "choose exactly one destination: --usb or --ssh"
fi
if [ -z "$USB_MOUNT" ] && [ -z "$SSH_HOST" ]; then
  usage
  die "missing destination: pass --usb or --ssh"
fi

if [ -z "$LOCAL_BUNDLE" ]; then
  LOCAL_BUNDLE="${HOME}/.koreader-notebooklm/auth-bundles/${PROFILE}-auth-bundle.json"
fi

case "$(cd "$(dirname "$LOCAL_BUNDLE")" 2>/dev/null && pwd -P || true)/$(basename "$LOCAL_BUNDLE")" in
  "$REPO_ROOT"/*)
    die "refusing to write/read auth bundle inside the repository: $LOCAL_BUNDLE"
    ;;
esac

if [ "$REFRESH" = "1" ] || [ ! -f "$LOCAL_BUNDLE" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    log "dry-run: would run Chrome login and write auth bundle to $LOCAL_BUNDLE"
  else
    log "Creating nlm-lite auth bundle with Chrome login."
    "$REPO_ROOT/scripts/nlm-lite-login.py" \
      --profile "$PROFILE" \
      --output "$LOCAL_BUNDLE" \
      --overwrite
  fi
else
  log "Reusing local auth bundle: $LOCAL_BUNDLE"
fi

if [ "$DRY_RUN" != "1" ]; then
  [ -f "$LOCAL_BUNDLE" ] || die "auth bundle does not exist: $LOCAL_BUNDLE"
  python3 - "$LOCAL_BUNDLE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    raise SystemExit(f"invalid auth bundle JSON: {exc}")

cookies = data.get("cookies")
if not cookies:
    raise SystemExit("invalid auth bundle: missing cookies")
base_url = str(data.get("base_url") or "")
if "notebooklm.google.com" not in base_url:
    raise SystemExit("invalid auth bundle: base_url is not NotebookLM")

account = data.get("email") or data.get("account") or ""
profile = data.get("profile") or ""
print("Auth bundle validated.")
if profile:
    print(f"  profile: {profile}")
if account:
    print(f"  account: {account}")
PY
else
  log "dry-run: would validate auth bundle JSON without printing secrets"
fi

settings_payload() {
  local auth_path="$1"
  local notebook_line='    ["direct_notebook_id"] = "",'
  if [ -n "$DIRECT_NOTEBOOK_ID" ]; then
    notebook_line="    [\"direct_notebook_id\"] = \"${DIRECT_NOTEBOOK_ID}\","
  fi
  cat <<LUA
return {
    ["backend"] = "lua-direct",
    ["direct_auth_bundle_path"] = "${auth_path}",
${notebook_line}
    ["enable_upload"] = true,
    ["language"] = "en",
    ["open_answer_automatically"] = true,
    ["show_prompt_buttons"] = true,
    ["timeout"] = 120,
    ["upload_mode"] = "multipart",
}
LUA
}

sync_usb() {
  local mount="$1"
  local settings_dir="${mount%/}/koreader/settings"
  local target_bundle="$settings_dir/notebooklm-auth-bundle.json"
  local target_settings="$settings_dir/notebooklm.lua"

  [ -d "$mount" ] || die "USB mount does not exist: $mount"
  log "Syncing auth bundle over USB."
  log "  destination: $target_bundle"
  run mkdir -p "$settings_dir"
  run cp "$LOCAL_BUNDLE" "$target_bundle"
  run chmod 600 "$target_bundle" 2>/dev/null || true
  if [ "$CONFIGURE" = "1" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      log "dry-run: would write $target_settings"
    else
      settings_payload "/mnt/us/koreader/settings/notebooklm-auth-bundle.json" > "$target_settings"
      chmod 600 "$target_settings" 2>/dev/null || true
    fi
  fi
}

sync_ssh() {
  local host="$1"
  local settings_path="/mnt/us/koreader/settings/notebooklm.lua"
  local ssh_opts=(-p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=2 -o ServerAliveCountMax=2)
  local scp_opts=(-P "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=2 -o ServerAliveCountMax=2)

  log "Syncing auth bundle over SSH."
  log "  destination: root@${host}:${REMOTE_BUNDLE}"
  run ssh "${ssh_opts[@]}" "root@${host}" 'mkdir -p /mnt/us/koreader/settings'
  run scp "${scp_opts[@]}" "$LOCAL_BUNDLE" "root@${host}:${REMOTE_BUNDLE}"
  run ssh "${ssh_opts[@]}" "root@${host}" "chmod 600 '$REMOTE_BUNDLE' 2>/dev/null || true"
  if [ "$CONFIGURE" = "1" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      log "dry-run: would write root@${host}:${settings_path}"
    else
      local tmp_settings
      tmp_settings="$(mktemp)"
      settings_payload "$REMOTE_BUNDLE" > "$tmp_settings"
      scp "${scp_opts[@]}" "$tmp_settings" "root@${host}:${settings_path}"
      rm -f "$tmp_settings"
      ssh "${ssh_opts[@]}" "root@${host}" "chmod 600 '$settings_path' 2>/dev/null || true"
    fi
  fi
}

if [ -n "$USB_MOUNT" ]; then
  sync_usb "$USB_MOUNT"
else
  sync_ssh "$SSH_HOST"
fi

log ""
log "Auth sync complete."
if [ "$CONFIGURE" = "1" ]; then
  log "  KOReader backend: lua-direct"
fi
if [ "$SMOKE" = "1" ]; then
  log "Next check: open KOReader and run NotebookLM -> Settings -> Lua direct smoke."
fi
