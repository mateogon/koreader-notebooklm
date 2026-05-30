# Auth Sync Cleanup and Implementation Plan

## Decision

Remove the auth broker path from the active product for now.

The main runtime direction is:

```text
Daily use:
KOReader on Kindle -> lua-direct -> NotebookLM

Occasional auth renewal:
Mac/PC -> Chrome login -> auth bundle -> USB/SSH sync -> Kindle
```

This keeps the Kindle self-contained for reading and NotebookLM requests, while
using a desktop only when Google auth needs to be refreshed. Existing auth tends
to last a long time, so this should be an infrequent maintenance action.

## Why Not Auth Broker Now

- The QR/phone flow cannot directly move Google/NotebookLM cookies from a normal
  phone browser to KOReader.
- A broker still needs a trusted helper with browser automation, so it is not
  simpler than a desktop sync tool.
- A LAN broker adds endpoints, pairing state, and security concerns for a flow
  that should be rare.
- If a real broker becomes useful later, it can be rebuilt quickly from the
  previous experiment.

## Target User Experience

### Recommended Beginner Flow: USB

```text
1. Connect Kindle by USB.
2. Run one command on Mac/PC.
3. Chrome opens if auth must be refreshed.
4. Tool writes/copies auth bundle into the mounted Kindle.
5. Tool updates KOReader NotebookLM settings.
6. User ejects Kindle and opens KOReader.
```

USB is less technical for most users because it avoids IP discovery and SSH
setup, but it requires exiting KOReader so the Kindle mounts as storage.

### Power User Flow: SSH

```text
1. Kindle is awake and SSH is enabled.
2. Run one command with host/port.
3. Tool writes/copies auth bundle over SCP.
4. Tool updates KOReader NotebookLM settings.
5. Optional smoke check.
```

SSH is faster during development but requires knowing the Kindle IP and keeping
the device awake.

## Cleanup Plan

Remove active auth broker code and UI:

- Delete `bridge/src/koreader_notebooklm_bridge/auth_broker/`.
- Delete `bridge/tests/test_auth_broker.py`.
- Delete `scripts/run-auth-broker-dev.sh`.
- Remove auth broker router/state from `bridge/src/koreader_notebooklm_bridge/app.py`.
- Remove `auth_broker_url` from `plugin/notebooklm.koplugin/settings.lua`.
- Remove `Refresh auth from broker` and auth broker URL UI from
  `plugin/notebooklm.koplugin/main.lua`.
- Remove `create_auth_session`, `get_auth_session`, `download_auth_bundle`, and
  `complete_auth_session` from `plugin/notebooklm.koplugin/client.lua`.
- Move `docs/auth-broker-plan.md` to `research/auth-broker-notes.md` or rewrite
  it as a postponed spike note.

Keep:

- `scripts/nlm-lite-login.py`.
- `bridge/src/koreader_notebooklm_bridge/notebooklm_lite/login.py`.
- `bridge/src/koreader_notebooklm_bridge/notebooklm_lite/auth.py`.
- `scripts/export-nlm-auth-bundle.py` if still useful for migrating existing
  `nlm` profiles.
- `scripts/import-auth-to-kindle.sh` only if folded into the new sync script or
  kept as an internal helper.

## New Script

Create:

```text
scripts/sync-auth-to-kindle.sh
```

The script should be the main user-facing command.

### Suggested CLI

```sh
scripts/sync-auth-to-kindle.sh --usb /Volumes/Kindle
scripts/sync-auth-to-kindle.sh --ssh 192.168.0.105 --port 2222
scripts/sync-auth-to-kindle.sh --usb /Volumes/Kindle --refresh
scripts/sync-auth-to-kindle.sh --ssh 192.168.0.105 --bundle ~/.koreader-notebooklm/auth-bundles/default-auth-bundle.json
```

Options:

```text
--usb <mount-path>           Kindle USB mount path.
--ssh <host>                 Kindle SSH host/IP.
--port <port>                SSH port, default 2222.
--profile <name>             Local auth profile, default default.
--bundle <path>              Reuse an existing auth bundle.
--refresh                    Force browser login and overwrite local bundle.
--notebook-id <id>           Optional default direct notebook id.
--no-configure               Copy bundle only, do not update notebooklm.lua.
--no-smoke                   Skip smoke validation.
--dry-run                    Print planned actions without writing.
```

Rules:

- Exactly one destination mode: `--usb` or `--ssh`.
- Do not print cookie values, CSRF tokens, headers, or auth JSON.
- Refuse to write auth bundles inside the repo unless explicitly overridden by a
  low-level developer-only flag.
- Default local bundle path:

```text
~/.koreader-notebooklm/auth-bundles/<profile>-auth-bundle.json
```

- Default Kindle bundle path:

```text
/mnt/us/koreader/settings/notebooklm-auth-bundle.json
```

- USB equivalent:

```text
<mount>/koreader/settings/notebooklm-auth-bundle.json
```

## Script Behavior

### 1. Resolve Local Auth Bundle

If `--bundle` is passed:

- Verify file exists.
- Validate it is JSON.
- Validate it has `cookies` and NotebookLM base URL/token fields where possible.

If no bundle exists or `--refresh` is passed:

- Run `scripts/nlm-lite-login.py --profile <profile> --output <bundle> --overwrite`.
- Open Chrome for login.
- Save bundle outside repo.

If bundle exists and no `--refresh`:

- Reuse it.
- Print age/account metadata only if available.

### 2. Resolve Destination

USB:

- Check `<mount>/koreader` exists or create `<mount>/koreader/settings`.
- Copy bundle to `<mount>/koreader/settings/notebooklm-auth-bundle.json`.
- Write/update `<mount>/koreader/settings/notebooklm.lua`.

SSH:

- Check connection with short timeout.
- Create `/mnt/us/koreader/settings`.
- Copy bundle with `scp`.
- Write/update `/mnt/us/koreader/settings/notebooklm.lua`.
- `chmod 600` bundle/settings if supported.

### 3. Update KOReader Settings

Write a minimal `notebooklm.lua` that preserves user-friendly defaults:

```lua
return {
    ["direct_auth_bundle_path"] = "/mnt/us/koreader/settings/notebooklm-auth-bundle.json",
    ["direct_notebook_id"] = "",
    ["enable_upload"] = true,
    ["language"] = "en",
    ["open_answer_automatically"] = true,
    ["show_prompt_buttons"] = true,
    ["timeout"] = 120,
    ["upload_mode"] = "multipart",
}
```

If we can safely patch existing settings instead of overwriting, prefer patching.
For the first implementation, overwriting is acceptable if the script clearly
states it will configure NotebookLM settings.

### 4. Smoke Validation

USB:

- Do not run Kindle-side smoke. Print next steps:

```text
Eject Kindle, open KOReader, run NotebookLM -> Settings -> Lua direct smoke.
```

SSH:

- Optional first version can skip smoke and print the same instruction.
- Later version can run KOReader's bundled `luajit` worker if path detection is
  reliable.

## Documentation Updates

Update:

- `README.md`: quick start with USB first, SSH second.
- `docs/setup-kindle.md`: replace broker flow with auth sync flow.
- `docs/setup-pc-auth.md`: explain `nlm-lite-login.py` and sync script.
- `docs/lua-port-plan.md`: mark auth as desktop-generated, Kindle-consumed.
- `.gitignore`: ensure auth bundles, cookies, books, generated answers, logs,
  temp data, and local downloaded repos are ignored.

Add:

- `docs/auth-sync.md`: one clean document for auth generation and Kindle sync.

## Implementation Order

1. Remove auth broker code/UI/tests/scripts.
2. Run bridge tests and Lua verifier to confirm cleanup.
3. Create `scripts/sync-auth-to-kindle.sh` with USB + SSH modes.
4. Reuse `nlm-lite-login.py` for refresh; avoid duplicating browser-login code.
5. Add dry-run and clear error messages.
6. Update docs and README.
7. Validate:

```sh
cd bridge
uv run --extra dev pytest -q
uv run --extra dev python ../scripts/verify-plugin-lua.py
git diff --check
```

8. Manual validation:

```text
[ ] USB sync writes bundle/settings to mounted Kindle.
[ ] SSH sync writes bundle/settings to live Kindle.
[ ] KOReader sees the synced auth bundle path.
[ ] Lua direct smoke passes.
[ ] Ask flow still works without bridge.
```

## Done Criteria

- No active auth broker code remains in bridge or plugin UI.
- The primary auth renewal path is one documented command.
- USB and SSH are both supported.
- The script never prints or commits secrets.
- README explains the real architecture honestly:

```text
Kindle runs NotebookLM requests directly. Mac/PC is only used to refresh auth.
```
