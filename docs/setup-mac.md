# macOS Setup

## Mock Bridge

From the repository root:

```bash
cd bridge
uv run --extra dev pytest
uv run uvicorn --app-dir src koreader_notebooklm_bridge.app:app --host 127.0.0.1 --port 8765
```

## Real NotebookLM Mode

This project does not implement NotebookLM auth directly. Use the existing `nlm` CLI auth flow:

```bash
nlm doctor
nlm notebook list --json
```

Then run the bridge with the `nlm` adapter:

```bash
cd bridge
KOREADER_NOTEBOOKLM_ADAPTER=nlm \
KOREADER_NOTEBOOKLM_DEFAULT_NOTEBOOK_ID=<NOTEBOOK_ID> \
uv run uvicorn --app-dir src koreader_notebooklm_bridge.app:app --host 0.0.0.0 --port 8765
```

For a non-default `nlm` profile:

```bash
KOREADER_NOTEBOOKLM_NLM_PROFILE=<PROFILE>
```

From KOReader on the same network, the bridge URL will be:

```text
http://<mac-lan-ip>:8765
```

## Real EPUB Smoke

With the bridge running in real `nlm` mode, run the protected smoke from
another shell:

```bash
KOREADER_NOTEBOOKLM_REAL_SMOKE=1 scripts/smoke-real-epub.sh
```

This creates a temporary NotebookLM notebook, uploads a generated EPUB through
the bridge multipart endpoint, asks a question, and deletes the temporary
notebook unless `KEEP_REAL_SMOKE_NOTEBOOK=1` is set.

Do not commit NotebookLM auth files, cookies, or `auth.json`.
