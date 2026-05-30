# Fresh PC Auth Setup

Purpose: create a NotebookLM auth bundle on Mac/PC and sync it to Kindle for
KOReader `lua-direct`.

The preferred flow does not require `nlm`:

```text
scripts/nlm-lite-login.py -> Chrome login -> auth bundle
scripts/sync-auth-to-kindle.sh -> USB/SSH copy to Kindle
```

## 1. Install Runtime

Install Python 3.11+ and `uv` on the PC.

`nlm` is optional. It is only useful if you want to export an existing
NotebookLM MCP/CLI profile.

Optional `nlm` install:

```sh
uv tool install notebooklm-mcp-cli
```

If it is already installed, upgrade it:

```sh
uv tool upgrade notebooklm-mcp-cli
```

Confirm the command is available:

```sh
nlm --version
```

## 2. Create an Auth Bundle

Preferred path:

```sh
scripts/nlm-lite-login.py --profile default --overwrite
```

This opens Chrome, waits for NotebookLM login, then writes outside the repo:

```text
~/.koreader-notebooklm/auth-bundles/default-auth-bundle.json
```

Named profile:

```sh
scripts/nlm-lite-login.py --profile koreader --overwrite
```

Fallback if you already have an `nlm` profile:

```sh
scripts/export-nlm-auth-bundle.py --profile <profile-name>
```

## 3. Sync to Kindle

```sh
scripts/sync-auth-to-kindle.sh --usb /Volumes/Kindle
```

or:

```sh
scripts/sync-auth-to-kindle.sh --ssh <kindle-ip> --port 2222
```

The sync script creates auth if needed, copies the bundle, and writes the
KOReader NotebookLM settings file.

Force a fresh login and sync:

```sh
scripts/sync-auth-to-kindle.sh --usb /Volumes/Kindle --refresh
```

## 4. Optional Bridge Development

The bridge can still run with `nlm-lite` for development:

```sh
cd bridge
KOREADER_NOTEBOOKLM_ADAPTER=nlm-lite \
KOREADER_NOTEBOOKLM_AUTH_BUNDLE=~/.koreader-notebooklm/auth-bundles/<profile-name>-auth-bundle.json \
KOREADER_NOTEBOOKLM_DEFAULT_NOTEBOOK_ID=<NOTEBOOK_ID> \
uv run uvicorn --app-dir src koreader_notebooklm_bridge.app:app --host 127.0.0.1 --port 8765
```

## 5. Smoke Test `nlm-lite`

In another shell:

```sh
scripts/smoke-nlm-lite.sh
```

If `KOREADER_NOTEBOOKLM_DEFAULT_NOTEBOOK_ID` is set in the bridge process,
the script also tests `/ask`.

To simulate the KOReader bridge flow without opening KOReader:

```sh
KOREADER_NOTEBOOKLM_BRIDGE_URL=http://127.0.0.1:8765 \
scripts/smoke-koreader-bridge-flow.sh
```

## Security Rules

- Do not commit `~/.notebooklm-mcp-cli/`.
- Do not commit `auth.json`, `cookies.json`, browser profile data, or exported
  auth bundles.
- Do not paste cookies into docs, issues, or logs.
- Do not expose auth export over LAN.
