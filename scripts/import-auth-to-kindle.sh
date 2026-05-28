#!/usr/bin/env bash
set -euo pipefail

# Copy a local nlm-lite auth bundle to a KOReader device over SSH.
# The bundle contains NotebookLM cookies/tokens. Treat it like a password.

KINDLE_HOST="${KOREADER_KINDLE_HOST:-${1:-}}"
KINDLE_PORT="${KOREADER_KINDLE_PORT:-2222}"
PROFILE="${KOREADER_NOTEBOOKLM_NLM_PROFILE:-default}"
LOCAL_BUNDLE="${KOREADER_NOTEBOOKLM_AUTH_BUNDLE:-}"
REMOTE_BUNDLE="${KOREADER_NOTEBOOKLM_REMOTE_AUTH_BUNDLE:-/mnt/us/koreader/settings/notebooklm-auth-bundle.json}"
CONFIGURE="${KOREADER_NOTEBOOKLM_CONFIGURE_KINDLE:-0}"
DIRECT_NOTEBOOK_ID="${KOREADER_NOTEBOOKLM_DIRECT_NOTEBOOK_ID:-}"
SSH_OPTS=(-p "$KINDLE_PORT" -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=2 -o ServerAliveCountMax=2)
SCP_OPTS=(-P "$KINDLE_PORT" -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=2 -o ServerAliveCountMax=2)

if [ -z "$KINDLE_HOST" ]; then
  echo "Usage: KOREADER_KINDLE_HOST=<kindle-ip> $0"
  echo "Optional: KOREADER_KINDLE_PORT=2222 KOREADER_NOTEBOOKLM_AUTH_BUNDLE=/path/bundle.json"
  exit 2
fi

if [ -z "$LOCAL_BUNDLE" ]; then
  LOCAL_BUNDLE="${HOME}/.koreader-notebooklm/auth-bundles/${PROFILE}-auth-bundle.json"
  echo "Exporting nlm profile '${PROFILE}' to a local auth bundle outside the repo."
  scripts/export-nlm-auth-bundle.py \
    --profile "$PROFILE" \
    --output "$LOCAL_BUNDLE" \
    --overwrite >/dev/null
fi

if [ ! -f "$LOCAL_BUNDLE" ]; then
  echo "Auth bundle does not exist: $LOCAL_BUNDLE" >&2
  exit 1
fi

echo "Copying auth bundle to Kindle over SSH."
ssh "${SSH_OPTS[@]}" "root@${KINDLE_HOST}" 'mkdir -p /mnt/us/koreader/settings'
scp "${SCP_OPTS[@]}" "$LOCAL_BUNDLE" "root@${KINDLE_HOST}:${REMOTE_BUNDLE}"
ssh "${SSH_OPTS[@]}" "root@${KINDLE_HOST}" "chmod 600 '$REMOTE_BUNDLE'"

if [ "$CONFIGURE" = "1" ]; then
  echo "Writing KOReader NotebookLM settings for lua-direct."
  remote_notebook_line=""
  if [ -n "$DIRECT_NOTEBOOK_ID" ]; then
    remote_notebook_line="    [\"direct_notebook_id\"] = \"${DIRECT_NOTEBOOK_ID}\","
  fi
  ssh "${SSH_OPTS[@]}" "root@${KINDLE_HOST}" "cat > /mnt/us/koreader/settings/notebooklm.lua <<'LUA'
return {
    [\"backend\"] = \"lua-direct\",
    [\"direct_auth_bundle_path\"] = \"${REMOTE_BUNDLE}\",
${remote_notebook_line}
    [\"enable_upload\"] = true,
    [\"open_answer_automatically\"] = true,
    [\"show_prompt_buttons\"] = true,
    [\"timeout\"] = 120,
    [\"upload_mode\"] = \"multipart\",
}
LUA
chmod 600 /mnt/us/koreader/settings/notebooklm.lua"
fi

echo "Auth bundle imported."
echo "  remote: $REMOTE_BUNDLE"
if [ "$CONFIGURE" = "1" ]; then
  echo "  settings: backend=lua-direct"
else
  echo "Set this path in KOReader: NotebookLM -> Settings -> Lua direct auth bundle"
fi
