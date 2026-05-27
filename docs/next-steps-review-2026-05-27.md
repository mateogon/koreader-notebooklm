# Next Steps Review - 2026-05-27

Source: ChatGPT Pro review based on the repository context pack generated on
2026-05-27.

## Executive Summary

According to the 2026-05-27 review, the project is more advanced than an
initial MVP, but it is not yet a truly usable MVP until two validations pass:

1. KOReader real UI using the `nlm` adapter.
2. Runtime on Kindle, Android, or Termux.

The current state has already validated the bridge, mock adapter, real KOReader
macOS mock flow, real EPUB upload through `nlm` from scripts, and the separation
`ui/main -> client.lua -> http.lua -> bridge`. The unproven paths remain `nlm`
triggered from the real UI and physical-device runtime.

## 1. Current Diagnosis

### What Is Working Well

The base architecture is correct. `client.lua` as the backend boundary is the
right decision: KOReader UI should not know whether the backend is the Mac
bridge, Termux, a small LAN server, or a future internal Kindle backend.

The plugin already covers much of the real flow:

- Tools menu.
- Highlight-menu actions.
- Book-to-notebook linking.
- Notebook creation.
- Multipart upload.
- Preset and custom prompts.
- `/ask`.
- Answer viewer.
- Basic settings.

This is beyond scaffold. The focus should now move from adding features to
making the real flow reliable.

The bridge is in a reasonable shape:

- FastAPI app.
- `mock` and `nlm` adapter factory.
- Clear endpoints.
- Tests for `/health`, `/notebooks`, `/books`, `/sources/upload`,
  `/sources/upload-file`, `/ask`, and `nlm` adapter parsing.

Using `nlm` through subprocess remains the right choice for this phase. It is
less elegant than importing NotebookLM internals directly, but it reduces
coupling to private Python APIs. The existing research already concluded that
`nlm` covers the target operations: list, create, upload, and ask.

Not implementing standalone NotebookLM auth is still the right call. Auth is
cookie/session/CSRF-oriented, not a clean API-key flow. Pulling that into this
repo now would add risk without unlocking the MVP.

### Real Technical Risks

The biggest risk is false confidence from mocks. The mock flow passed in real
KOReader macOS, and the real `nlm` flow passed from scripts, but the important
combination is still unproven:

```text
KOReader real UI -> bridge adapter=nlm -> real NotebookLM
```

The second risk is that the bridge dev script may be inconsistent with the
docs. `docs/setup-kindle.md` says to start the bridge with
`KOREADER_NOTEBOOKLM_HOST=0.0.0.0`, but `scripts/run-bridge-dev.sh` may still be
hardcoded to `127.0.0.1`. If so, device testing will fail even if the bridge is
otherwise working.

Third risk: long requests can block the KOReader UI. `send_ask`,
`create_notebook`, and `upload_source` are synchronous from UI callbacks.
`UIManager:scheduleIn(0.1, ...)` avoids blocking on the button tap itself, but
the scheduled callback can still wait on socket, `nlm`, or NotebookLM for a long
time.

Fourth risk: multipart upload reads full files into memory. In Lua, `http.lua`
opens the file and reads it with `file:read("*all")`, then builds the multipart
body as one string. For small EPUB files this is acceptable; for large PDFs or
books on Kindle this can be a problem. The bridge has a related issue if
`/sources/upload-file` reads the whole upload before writing.

Fifth risk: `book_id` may be unstable. It is currently derived from
`path|title|author`, which changes if a file moves, is renamed, or is tested
across Mac and Kindle with different paths.

Sixth risk: exposing the bridge on LAN without auth. If the bridge listens on
`0.0.0.0` with the real `nlm` adapter, another device on the network could call
endpoints that create notebooks, upload files, and ask through the user's
NotebookLM session. This does not require Google auth work, but it does suggest
a simple bridge token.

### Fragile Or Overbuilt Areas

The UI is slightly ahead of the real validation. It already has create,
create+upload, list, link, prompt buttons, and settings. That is useful for
exploration, but to close the MVP the scope should narrow to:

```text
Status -> Setup/link/create -> Ask preset/custom -> Answer
```

The prompt buttons in the highlight menu may be too invasive. Showing
`Ask NotebookLM` plus several presets is good for power users, but it may
saturate the menu. Consider defaulting to only `Ask NotebookLM`, with presets in
the internal picker.

The bridge JSON store is fine for the prototype, but fragile for concurrency
and corruption. It reads/writes `books.json` without locking or atomic writes.
SQLite is not necessary yet, but atomic writes are a reasonable next step.

## 2. Recommended Next Phase

The next milestone should be:

```text
MVP-real-mac:
KOReader macOS UI real -> bridge adapter=nlm -> real NotebookLM
```

Do not go to Kindle or Termux first. First validate that the already implemented
real UI works with real `nlm` latency, errors, and payloads.

### What Not To Do Yet

Do not implement standalone NotebookLM auth yet.

Do not replace subprocess calls with direct imports from `notebooklm_tools` yet.
Stabilize the HTTP contract first.

Do not attempt all-in-Kindle yet. Keep it as a later experimental path.

Do not do a large UI refactor. The UI is already good enough for validation, and
large UI changes now could hide real network, upload, or NotebookLM bugs.

### Suggested Order

```text
P0. Fix run-bridge-dev.sh so it respects HOST/PORT.
P0. Run KOReader macOS UI with adapter=nlm.
P0. Validate real ask without upload from UI.
P0. Validate real link/create from UI.
P1. Validate real create+upload from UI with a small EPUB.
P1. Improve visible KOReader errors for auth/timeout/upload.
P1. Run first Kindle/Android mock test.
P1. Repeat Kindle/Android with adapter=nlm.
```

## 3. Validation Checklist

### KOReader macOS, Mock Adapter

Use this as a regression loop before changes:

```text
[ ] Bridge mock responds to /health.
[ ] KOReader loads plugin without stack traceback.
[ ] NotebookLM -> Status shows Bridge OK.
[ ] Current book setup allows create/link.
[ ] Link persists when setup is reopened.
[ ] Highlight menu shows Ask NotebookLM.
[ ] Custom ask opens answer viewer.
[ ] Preset ask opens answer viewer.
[ ] Bridge offline shows a legible error.
```

### KOReader macOS, `nlm` Adapter

This is the most important validation now:

```text
[ ] Start bridge with adapter=nlm and host 127.0.0.1 for KOReader macOS.
[ ] NotebookLM -> Status shows Bridge OK (nlm).
[ ] Current book setup -> List shows real notebooks.
[ ] Use ID links a real existing notebook.
[ ] Highlight -> Ask NotebookLM -> Custom returns a real answer.
[ ] Highlight -> preset returns a real answer.
[ ] Answer viewer shows answer plus references/citations if returned.
[ ] Restart KOReader and confirm the book remains linked.
[ ] Stop bridge and confirm a legible error.
[ ] Check KOReader logs: no stack traceback.
[ ] Check bridge logs: no JSON parse errors or unexpected timeouts.
```

Then validate creation and upload:

```text
[ ] Current book setup -> Create creates a real notebook.
[ ] Create+Upload uploads a small real EPUB.
[ ] Ask about uploaded EPUB text returns an answer with citation/reference.
[ ] Confirm temporary notebook/source can be cleaned up manually.
```

### Kindle / Android / Termux

Test mock first, then `nlm`:

```text
[ ] Install plugin with --copy, not symlink.
[ ] Mac bridge listens on 0.0.0.0.
[ ] Plugin bridge URL uses Mac LAN IP, not 127.0.0.1.
[ ] Status OK from device.
[ ] Mock setup/link works.
[ ] Mock highlight ask works.
[ ] Answer viewer opens and is legible on e-ink or small screen.
[ ] Multipart mock upload works with a real device book.
[ ] No stack traces in crash.log or logs.
```

Then repeat with:

```text
KOREADER_NOTEBOOKLM_ADAPTER=nlm
```

Start with link existing notebook plus ask. Create+upload can come later.

### MVP Usable Criteria

Call it usable when:

```text
[ ] In real KOReader, not only stubs, text can be selected.
[ ] The book can be linked to a real notebook.
[ ] The link persists after restarting KOReader.
[ ] A real custom question can be sent to NotebookLM.
[ ] At least one real preset can be used.
[ ] The response is complete and legible.
[ ] Bridge/auth/NotebookLM failures show understandable errors.
[ ] It works in KOReader macOS and at least one physical or Android/Termux device.
[ ] There are no Lua stack traces.
[ ] No auth/cookies are stored in the repo.
```

Do not require automatic create+upload for the first usable MVP. Treat that as
MVP+.

## 4. Concrete Technical Improvements

### Plugin Lua / KOReader UI

Reduce UI blocking risk. Use differentiated timeouts:

- short for health/list;
- medium for ask;
- long for upload.

Put `Create+Upload` behind explicit confirmation:

```text
Uploading this file to NotebookLM can take time and will transfer the book to
the bridge. Continue?
```

Consider making direct prompt buttons disabled by default, with only
`Ask NotebookLM` visible in the highlight menu.

Keep the current Markdown-file plus `TextViewer.openFile` answer viewer for now.
Do not implement a full Markdown renderer yet.

Normalize citations in the answer output:

```text
Answer
References
  [1] source title / cited text
Sources used
Raw metadata at the end if needed
```

### Bridge FastAPI

Fix `run-bridge-dev.sh` to respect host and port:

```sh
HOST="${KOREADER_NOTEBOOKLM_HOST:-127.0.0.1}"
PORT="${KOREADER_NOTEBOOKLM_PORT:-8765}"
exec uv run uvicorn --app-dir src koreader_notebooklm_bridge.app:app --host "$HOST" --port "$PORT"
```

Make `/health` more useful without exposing secrets:

```json
{
  "ok": true,
  "adapter": "nlm",
  "default_notebook_id": "...",
  "nlm_command": "nlm",
  "nlm_profile": "default-or-null",
  "data_dir": "..."
}
```

Add an optional LAN token:

```text
KOREADER_NOTEBOOKLM_API_TOKEN=...
```

Require this header only when configured:

```http
X-KOReader-NotebookLM-Token: ...
```

Improve normalized `nlm` errors:

```json
{
  "detail": "...",
  "error_type": "auth_failed|timeout|nlm_not_found|parse_error|upload_failed"
}
```

### Persistence And Config

Improve `book_id` stability over time:

```text
book_id = hash(path + title + author + file_size + maybe mtime)
```

Better future path:

```text
EPUB identifier metadata if exposed
fallback partial content hash
fallback path/title/author
```

For the bridge JSON store:

```text
books.json.tmp -> fsync/write -> rename books.json
```

If corrupt JSON is found:

```text
books.json.corrupt.<timestamp>
```

Do not migrate to SQLite yet unless real usage creates pressure.

### EPUB And Upload Handling

Minimum improvements:

```text
[ ] Validate extension/size before upload.
[ ] Show confirmation with filename and size.
[ ] In bridge, stream UploadFile to disk by chunks.
[ ] In Lua, avoid file:read("*all") for large files or add a size limit.
[ ] Clean temporary uploads after nlm source upload unless debug mode is enabled.
```

For MVP, a simple Lua size limit or explicit warning is enough to avoid memory
failure on Kindle.

### Response Rendering

Do not implement full Markdown rendering yet. Small useful improvements:

```text
[ ] Sanitize selected_text/answer to avoid accidental huge files.
[ ] Truncate selected_text in display if huge, while still sending full text.
[ ] Show references before raw citations when both exist.
```

Optional later:

```text
notebooklm-last-answer.md
notebooklm-answer-<timestamp>.md
```

For MVP, `last-answer` is acceptable.

## 5. Actionable Work Plan

### P0 - Make The Bridge Listen On LAN When Requested

Files:

```text
scripts/run-bridge-dev.sh
docs/setup-kindle.md
docs/setup-mac.md
```

Tasks:

```text
[ ] Use KOREADER_NOTEBOOKLM_HOST and KOREADER_NOTEBOOKLM_PORT in the script.
[ ] Echo the real host/port.
[ ] Test KOREADER_NOTEBOOKLM_HOST=0.0.0.0 scripts/run-bridge-dev.sh.
[ ] Curl http://<mac-ip>:8765/health from another device.
```

### P0 - Validate KOReader macOS UI With `nlm`

Likely files if issues appear:

```text
plugin/notebooklm.koplugin/ui.lua
plugin/notebooklm.koplugin/client.lua
plugin/notebooklm.koplugin/http.lua
bridge/src/koreader_notebooklm_bridge/adapters/notebooklm.py
```

Tasks:

```text
[ ] Start bridge with adapter=nlm.
[ ] Use an existing notebook with a source already loaded.
[ ] In KOReader macOS, configure Bridge URL.
[ ] Use ID to link notebook.
[ ] Ask custom.
[ ] Ask preset.
[ ] Inspect answer viewer.
[ ] Inspect bridge and KOReader logs.
```

Do not test create+upload in the first pass.

### P0 - Improve Visible `nlm` Errors

Files:

```text
bridge/src/koreader_notebooklm_bridge/adapters/notebooklm.py
bridge/src/koreader_notebooklm_bridge/adapters/errors.py
bridge/src/koreader_notebooklm_bridge/routes/ask.py
bridge/src/koreader_notebooklm_bridge/routes/notebooks.py
bridge/src/koreader_notebooklm_bridge/routes/sources.py
plugin/notebooklm.koplugin/ui.lua
```

Tasks:

```text
[ ] Differentiate nlm not found, timeout, auth failed, and JSON parse errors.
[ ] Truncate stderr/stdout while preserving useful cause.
[ ] Show short KOReader errors, not giant dumps.
[ ] Add tests for timeout/auth-like stderr/JSON parse.
```

### P0 - Real Create/Link Without Upload

Files:

```text
plugin/notebooklm.koplugin/ui.lua
bridge/src/koreader_notebooklm_bridge/adapters/notebooklm.py
```

Tasks:

```text
[ ] Current book setup -> Create.
[ ] Verify notebook was created in NotebookLM.
[ ] Verify /books/link.
[ ] Restart KOReader and verify persistence.
[ ] Delete temporary notebook manually or by script.
```

### P1 - Real Create+Upload From KOReader UI

Likely files:

```text
plugin/notebooklm.koplugin/http.lua
plugin/notebooklm.koplugin/client.lua
bridge/src/koreader_notebooklm_bridge/routes/sources.py
bridge/src/koreader_notebooklm_bridge/adapters/notebooklm.py
```

Tasks:

```text
[ ] Use a small EPUB.
[ ] Confirm KOReader exposes a readable file path.
[ ] Confirm multipart reaches the bridge.
[ ] Confirm nlm source add --file --wait.
[ ] Confirm source_id is saved.
[ ] Ask something that requires the uploaded source.
```

### P1 - Minimal Bridge Security

Files:

```text
bridge/src/koreader_notebooklm_bridge/config.py
bridge/src/koreader_notebooklm_bridge/routes/dependencies.py
plugin/notebooklm.koplugin/settings.lua
plugin/notebooklm.koplugin/http.lua
plugin/notebooklm.koplugin/client.lua
docs/setup-kindle.md
```

Tasks:

```text
[ ] Add optional API token.
[ ] If configured in bridge, require header.
[ ] Add KOReader setting.
[ ] Document recommendation when host=0.0.0.0.
```

Do not block localhost MVP on this, but add it before regular LAN/hotspot use.

### P1 - First Kindle/Android Mock Test

Files:

```text
scripts/install-plugin-dev.sh
scripts/koreader-runtime-preflight.sh
docs/setup-kindle.md
```

Tasks:

```text
[ ] Install plugin with --copy.
[ ] Run Mac bridge mock with host 0.0.0.0.
[ ] Configure bridge URL in KOReader.
[ ] Test status, setup, custom ask, preset ask, answer viewer.
[ ] Inspect crash.log.
```

### P1 - First Kindle/Android `nlm` Test

Use the same flow with:

```text
KOREADER_NOTEBOOKLM_ADAPTER=nlm
```

Do not require create+upload first. Start with an existing linked notebook plus
ask.

### P2 - Reduce Upload Memory Pressure

Files:

```text
plugin/notebooklm.koplugin/http.lua
bridge/src/koreader_notebooklm_bridge/routes/sources.py
```

Tasks:

```text
[ ] Add configurable size limit.
[ ] Write UploadFile by chunks in the bridge.
[ ] Warn or block large files in Lua.
[ ] Clean temporary uploads after source upload.
```

### P2 - Improve `book_id`

Files:

```text
plugin/notebooklm.koplugin/storage.lua
bridge/src/koreader_notebooklm_bridge/models.py
docs/api.md
```

Tasks:

```text
[ ] Add file_size/mtime to book context if available.
[ ] Consider EPUB identifier if KOReader exposes it.
[ ] Maintain compatibility with existing links.
```

### P2 - Align Roadmap Docs

Files:

```text
docs/roadmap.md
docs/validation-audit.md
README.md
```

The roadmap is behind the audit. Some items are still presented as future work
even though they are implemented in mock/macOS form. Align the docs so the next
contributor does not work from stale state.

## Final Recommendation

Keep the architecture:

```text
KOReader plugin Lua -> client.lua -> bridge HTTP -> adapter nlm
```

Keep delegating auth to `nlm`.

Change the focus now: stop adding features and close real validation.

The next milestone should be:

```text
MVP real adapter validation
```

Definition:

```text
KOReader macOS real UI can link a real notebook, ask through adapter=nlm,
show the answer, persist the link, and recover with legible errors.
```

After that:

```text
Device MVP:
Kindle/Android -> Mac bridge mock -> Mac bridge nlm
```

Only then revisit Termux/mobile-host or all-in-Kindle. The all-in-Kindle path
should remain open, but not active yet.
