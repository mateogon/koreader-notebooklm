# Fresh PC Auth Setup

Purpose: set up NotebookLM auth on a new desktop machine so the bridge can run
with either `nlm` or `nlm-lite`.

`nlm-lite` does not implement Google login. It only reads existing local auth
state or an explicit auth bundle. For now, the simplest fresh setup is:

```text
install nlm -> run nlm login -> verify nlm doctor -> run bridge adapter=nlm-lite
```

This uses `nlm` only as the auth bootstrap. In `nlm-lite` mode, bridge requests
do not call the `nlm` subprocess.

## 1. Install Runtime

Install Python 3.11+ and `uv` on the PC.

Then install the NotebookLM CLI:

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

## 2. Login From Scratch

Run:

```sh
nlm login
```

Follow the browser login flow. This creates local auth/profile state under the
user's home directory, typically:

```text
~/.notebooklm-mcp-cli/
```

For multiple Google accounts, use a named profile:

```sh
nlm login --profile <profile-name>
nlm login switch <profile-name>
```

For WSL, `nlm login --wsl` may be useful.

## 3. Verify Auth

Run:

```sh
nlm doctor
nlm notebook list --json
```

Expected result:

- `nlm doctor` reports cookies present.
- `nlm notebook list --json` returns a JSON list.
- No auth files are copied into this repository.

## 4. Export an `nlm-lite` Auth Bundle

After `nlm login` works, export a portable auth bundle:

```sh
scripts/export-nlm-auth-bundle.py --profile <profile-name>
```

By default this writes outside the repo:

```text
~/.notebooklm-mcp-cli/auth-bundles/<profile-name>-auth-bundle.json
```

The file contains cookies and NotebookLM page tokens. Treat it like a password:
do not commit it, paste it, or put it in regular logs.

To overwrite an old bundle after re-login:

```sh
scripts/export-nlm-auth-bundle.py --profile <profile-name> --overwrite
```

## 5. Run Bridge With `nlm-lite`

From this repo:

```sh
cd bridge
KOREADER_NOTEBOOKLM_ADAPTER=nlm-lite \
KOREADER_NOTEBOOKLM_AUTH_BUNDLE=~/.notebooklm-mcp-cli/auth-bundles/<profile-name>-auth-bundle.json \
KOREADER_NOTEBOOKLM_DEFAULT_NOTEBOOK_ID=<NOTEBOOK_ID> \
uv run uvicorn --app-dir src koreader_notebooklm_bridge.app:app --host 127.0.0.1 --port 8765
```

For local development, `nlm-lite` can still read a named `nlm` profile directly:

```sh
KOREADER_NOTEBOOKLM_NLM_PROFILE=<profile-name>
```

The explicit auth bundle path is preferred for portability testing because it is
closer to the future Kindle/mobile flow and does not require the `nlm` CLI at
bridge runtime.

## 6. Smoke Test `nlm-lite`

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
- Do not expose `nlm-lite` auth export over LAN. Auth export/pairing is future
  work and must require explicit local authorization.
