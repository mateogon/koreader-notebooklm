# Validation Audit

Audit date: 2026-05-26

Objective audited: implement `docs/implementation-plan.md`.

## Summary

The bridge, adapter boundary, KOReader plugin modules, mock flow, real
`nlm` EPUB bridge flow, and KOReader macOS arm64 runtime flow are implemented
and locally verified. The real KOReader UI loaded the plugin, checked bridge
status, created/uploaded/linked a mock notebook, selected text from an EPUB,
sent preset and custom highlighted-text questions, and opened the Markdown
answer viewer.

The remaining unproven items are physical Kindle/Android runtime behavior and
triggering the `nlm` adapter from inside the real KOReader UI. The bridge-side
real `nlm` EPUB upload and ask path has been validated separately.

## Evidence

### Bridge Tests

Command:

```sh
cd bridge && uv run --extra dev pytest
```

Result:

```text
19 passed
```

Coverage relevance:

- `/health`
- `/notebooks`
- `/books/{book_id}`
- `/books/link`
- `/sources/upload`
- `/sources/upload-file`
- `/ask`
- `nlm` adapter parsing and command behavior

### Plugin Lua Runtime Smoke

Command:

```sh
uv run --with lupa scripts/verify-plugin-lua.py
```

Result:

```text
plugin runtime smoke ok
```

Coverage relevance:

- plugin loads
- Tools-menu registration
- highlight-menu registration
- highlight-menu callback execution
- setup skip action
- settings menu for source upload, upload mode, and prompt-button defaults
- link-existing notebook picker flow
- create-notebook flow
- multipart upload flow
- JSON path upload flow
- book-link persistence
- preset prompt ask flow
- custom question ask flow
- ask flow
- `/ask` payload includes notebook id, selected text, prompt, book title,
  author, path, and reading position
- answer file creation
- answer viewer open call
- source/reference/citation rendering
- offline bridge error display
- long selected text and long answer file writing
- upload feature flag hides `Create+Upload` and blocks upload calls

This uses lightweight Lua stubs, not real KOReader widgets.

### KOReader Runtime Preflight

Command:

```sh
scripts/koreader-runtime-preflight.sh [koreader-plugins-dir] [bridge-url]
```

Coverage relevance:

- verifies local plugin source files
- verifies installed plugin files when a KOReader plugins directory is provided
- checks bridge `/health` when reachable
- lists KOReader log candidates near the provided plugins directory
- prints the remaining manual KOReader acceptance steps

This prepares the real runtime validation loop, but it does not replace opening
KOReader and exercising the UI.

### Real KOReader macOS Runtime Smoke

Runtime source:

- KOReader v2026.03 macOS arm64 GitHub Actions artifact
- workflow run: <https://github.com/koreader/koreader/actions/runs/23214193860>
- artifact: `KOReader-arm64-2026.03.7z`

Commands and actions:

```sh
scripts/smoke-koreader-macos.sh
```

Result:

- KOReader opened the generated EPUB on macOS arm64.
- KOReader debug logs included `Plugin loaded notebooklm` and
  `RD loaded plugin notebooklm at plugins/notebooklm.koplugin`.
- The automated smoke checked that no Lua `stack traceback` appeared.
- `NotebookLM -> Status` showed `Bridge: OK (mock)`.
- `NotebookLM -> Current book setup -> Create+Upload` completed with:
  `Notebook created, source uploaded, and book linked.`
- A second `NotebookLM -> Status` showed the book linked to
  `mock-created-notebook`.
- Bridge logs showed:
  - `GET /books/book-b137ed21` initially returned 404
  - `GET /health` returned 200
  - `POST /notebooks` returned 200
  - `POST /sources/upload-file` returned 200
  - `POST /books/link` returned 200
  - subsequent `GET /books/book-b137ed21` returned 200

This proves real KOReader plugin loading, status, setup, multipart upload, and
book-link persistence in the macOS desktop runtime.

### Real KOReader Highlight Ask Smoke

Runtime source:

- same KOReader v2026.03 macOS arm64 artifact used by
  `scripts/smoke-koreader-macos.sh`

Actions:

- selected real EPUB text in KOReader with macOS event injection
- KOReader showed the native highlight menu with:
  - `Ask NotebookLM`
  - `Contexto (NotebookLM)`
  - `Aclara termino (NotebookLM)`
  - `Explica simple (NotebookLM)`
  - `3 bullets (NotebookLM)`
  - `Por que importa (NotebookLM)`
- tapped `Explica simple (NotebookLM)` on an unlinked book
- completed `Current book setup -> Create+Upload`
- KOReader opened
  `/Users/mateo/Library/Application Support/koreader/settings/notebooklm-last-answer.md`
- selected the same text again, tapped `Ask NotebookLM -> Custom`, entered a
  custom question, and opened the answer viewer again

Observed answer file:

```markdown
# NotebookLM

Prompt: Custom
Notebook ID: mock-created-notebook

## Selected text

KOReader NotebookLM plugin runtime smoke

## Answer

Mock NotebookLM response for prompt: What is this sentence about?

Selected passage: KOReader NotebookLM plugin runtime smoke
```

Bridge evidence:

- `GET /books/book-f58d0c1d` returned 404 before setup
- `POST /notebooks` returned 200
- `POST /sources/upload-file` returned 200
- `POST /books/link` returned 200
- subsequent `GET /books/book-f58d0c1d` returned 200
- `POST /ask` returned 200 twice, once for the preset prompt and once for the
  custom question

This proves the real KOReader highlighted-text menu, setup handoff, mock ask
request, and answer viewer path in the macOS desktop runtime.

### Mock Plugin-Shaped Bridge Flow

Command:

```sh
scripts/smoke-plugin-flow.sh
```

Result:

- notebook created through bridge mock adapter
- source uploaded through `/sources/upload-file`
- book linked through `/books/link`
- mapping retrieved through `/books/{book_id}`
- highlighted text asked through `/ask`

### Real `nlm` EPUB Flow

Command shape:

```sh
KOREADER_NOTEBOOKLM_ADAPTER=nlm ./scripts/run-bridge-dev.sh
KOREADER_NOTEBOOKLM_REAL_SMOKE=1 scripts/smoke-real-epub.sh
```

Result:

- `nlm doctor` passed
- temporary NotebookLM notebook created
- generated EPUB uploaded through bridge multipart endpoint
- `POST /ask` returned an answer
- response included citation/reference data for the uploaded EPUB source
- temporary NotebookLM notebook deleted

This proves EPUB upload and query through the Mac bridge and `nlm` adapter.

## Requirement Status

| Requirement | Status | Evidence |
| --- | --- | --- |
| UI code depends on `client.lua`, not direct HTTP | Done | `main.lua` and `ui.lua` call `client.lua`; `http.lua` owns transport |
| Internal plugin modules avoid generic `require` cache collisions | Done | `main.lua` loads plugin-local modules through `dofile(self.path .. ...)`; `client.lua` receives `http.lua` by injection |
| Bridge URL and settings are configurable | Done | `settings.lua`; `NotebookLM -> Bridge URL`; `NotebookLM -> Settings`; Lua verifier checks settings toggles |
| Source upload feature flag | Done, stub-verified | `settings.lua`; Lua verifier checks hidden setup upload action and disabled upload error |
| Book id is derived and link metadata stored locally | Done | `storage.lua`; Lua verifier exercises persistence |
| Bridge stores book-to-notebook mapping | Done | `/books/link`; pytest and smoke flow |
| Link existing notebook | Done, stub-verified | `ui.lua` notebook picker; Lua verifier invokes picker callback and checks saved link |
| Create notebook | Done | `/notebooks`; Lua verifier and smoke scripts |
| Create notebook and upload source | Done | `ui.lua`; `/sources/upload-file`; Lua verifier; real EPUB smoke; real KOReader macOS UI smoke |
| Highlight menu actions | Done | `main.lua`; Lua verifier executes highlight-menu callbacks; real KOReader macOS UI showed NotebookLM highlight actions |
| Preset prompts | Done | `prompts.lua`; `main.lua` prompt buttons |
| Custom question | Done | `ui.lua` custom dialog; Lua verifier invokes custom ask callback; real KOReader macOS UI sent a custom question |
| Ask bridge endpoint | Done | `/ask`; pytest; mock and real smoke; Lua verifier checks selected text, prompt, notebook id, and book context payload; real KOReader macOS UI produced two `/ask` requests |
| Scrollable answer view | Done | `TextViewer.openFile`; Lua verifier checks answer, long selected text, long answer text, source, reference, and citation output; real KOReader macOS UI opened `notebooklm-last-answer.md` |
| Offline bridge error display | Done, stub-verified | Lua verifier forces network error and checks status dialog text |
| Install/debug preflight | Done | `scripts/koreader-runtime-preflight.sh`; setup docs |
| KOReader macOS launch smoke | Done | `scripts/smoke-koreader-macos.sh` downloads/runs KOReader v2026.03 arm64, verifies plugin load, and checks no Lua stack trace |
| Multipart upload for device-to-bridge | Done | `/sources/upload-file`; pytest; mock and real smoke; Lua verifier checks default multipart client path |
| JSON path upload for Mac-local smoke tests | Done | `/sources/upload`; pytest; Lua verifier checks `upload_mode=path` payload |
| Real EPUB accepted by `nlm` path | Done | `scripts/smoke-real-epub.sh` run on 2026-05-26 |
| KOReader real desktop runtime | Done for current mock MVP | macOS arm64 KOReader v2026.03 UI smoke loads plugin, checks bridge status, links current book, selects highlighted text, sends preset/custom asks, and opens the answer viewer |
| KOReader real highlighted ask flow | Done for current mock MVP | Validated through real KOReader macOS UI with selected EPUB text and two successful bridge `/ask` calls |
| KOReader real UI with `nlm` adapter | Not proven | Real `nlm` bridge flow was validated from smoke scripts, not triggered from KOReader UI |
| Physical Kindle/Android runtime | Not proven | Deferred until device/emulator validation |
| All-in-Kindle backend | Deferred | Plan explicitly keeps this future-only |

## KOReader Runtime Acceptance Checklist

Use this checklist on a Kindle, emulator, or runnable desktop KOReader build:

1. Install plugin with:

   ```sh
   scripts/install-plugin-dev.sh /path/to/koreader/plugins --copy
   ```

2. Start bridge in mock mode:

   ```sh
   KOREADER_NOTEBOOKLM_HOST=0.0.0.0 scripts/run-bridge-dev.sh
   ```

3. Run preflight:

   ```sh
   scripts/koreader-runtime-preflight.sh /path/to/koreader/plugins http://<mac-lan-ip>:8765
   ```

4. In KOReader, set:

   ```text
   NotebookLM -> Bridge URL -> http://<mac-lan-ip>:8765
   ```

5. Open a book.
6. Confirm `NotebookLM -> Status` shows bridge OK.
7. Run `NotebookLM -> Current book setup`.
8. Create a notebook in mock mode.
9. Reopen setup and confirm the book remains linked.
10. Highlight text.
11. Tap `Ask NotebookLM`.
12. Send a custom question.
13. Confirm answer opens in KOReader.
14. Highlight text again.
15. Tap a preset prompt such as `Explica simple (NotebookLM)`.
16. Confirm answer opens in KOReader.
17. Stop bridge and confirm plugin shows a readable bridge error.
18. Inspect KOReader logs for stack traces.

After mock mode passes, repeat with:

```sh
KOREADER_NOTEBOOKLM_ADAPTER=nlm KOREADER_NOTEBOOKLM_HOST=0.0.0.0 scripts/run-bridge-dev.sh
```

Acceptance requires no Lua stack traces, successful link persistence, successful
ask flow, and readable answer display.
