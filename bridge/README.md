# Bridge

Local HTTP bridge for KOReader NotebookLM.

Current status: local HTTP bridge with two adapter modes:

- `mock`: no Google, NotebookLM, MCP, or auth calls.
- `nlm`: calls the local `nlm` CLI by subprocess. Auth stays in the normal `nlm` profile storage; this bridge does not copy cookies or `auth.json`.

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
