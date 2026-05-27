# Bridge

Local HTTP bridge for KOReader NotebookLM.

Current status: local HTTP bridge with three adapter modes:

- `mock`: no Google, NotebookLM, MCP, or auth calls.
- `nlm`: calls the local `nlm` CLI by subprocess. Auth stays in the normal `nlm` profile storage; this bridge does not copy cookies or `auth.json`.
- `nlm-lite`: experimental direct HTTP adapter. It reads existing local NotebookLM auth state or an explicit auth bundle, but does not implement Google login, import `notebooklm_tools`, or call the `nlm` subprocess.

## Development

From the repository root:

```bash
cd bridge
uv run --extra dev pytest
uv run uvicorn --app-dir src koreader_notebooklm_bridge.app:app --host 127.0.0.1 --port 8765
```

To run against the real local `nlm` CLI:

```bash
KOREADER_NOTEBOOKLM_ADAPTER=nlm \
KOREADER_NOTEBOOKLM_DEFAULT_NOTEBOOK_ID=<NOTEBOOK_ID> \
uv run uvicorn --app-dir src koreader_notebooklm_bridge.app:app --host 127.0.0.1 --port 8765
```

If you use a non-default `nlm` profile, set:

```bash
KOREADER_NOTEBOOKLM_NLM_PROFILE=<PROFILE>
```

To run the experimental direct adapter:

```bash
KOREADER_NOTEBOOKLM_ADAPTER=nlm-lite \
KOREADER_NOTEBOOKLM_DEFAULT_NOTEBOOK_ID=<NOTEBOOK_ID> \
uv run uvicorn --app-dir src koreader_notebooklm_bridge.app:app --host 127.0.0.1 --port 8765
```

Optional `nlm-lite` settings:

```bash
KOREADER_NOTEBOOKLM_AUTH_BUNDLE=/path/to/auth-bundle.json
KOREADER_NOTEBOOKLM_BASE_URL=https://notebooklm.google.com
KOREADER_NOTEBOOKLM_DIRECT_TIMEOUT_SECONDS=120
KOREADER_NOTEBOOKLM_UPLOAD_WAIT_SECONDS=600
```

Before real mode, verify auth outside the bridge:

```bash
nlm doctor
nlm notebook list --json
```

With the bridge running in `mock` mode, run the full plugin-shaped smoke flow:

```bash
../scripts/smoke-plugin-flow.sh
```

With the bridge running in real `nlm` mode, run the protected EPUB smoke:

```bash
KOREADER_NOTEBOOKLM_REAL_SMOKE=1 ../scripts/smoke-real-epub.sh
```

Endpoints:

- `GET /health`
- `GET /notebooks`
- `POST /notebooks`
- `GET /books/{book_id}`
- `POST /books/link`
- `POST /sources/upload`
- `POST /sources/upload-file`
- `POST /ask`

`POST /sources/upload` is for bridge-local file paths. `POST
/sources/upload-file` is multipart upload for KOReader devices that need to
send the book file to the bridge.

## Auth

Do not copy auth files into this repository. The `nlm` adapter delegates to the installed `nlm` command, which reads its own configured profile from `~/.notebooklm-mcp-cli`.

The `nlm-lite` adapter may read the same local profile/cache as a development convenience, or an explicit auth bundle outside the repo. It must not log cookies, CSRF tokens, request headers, or auth bundle contents.
