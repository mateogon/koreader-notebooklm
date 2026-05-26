# Validation Audit

Audit date: 2026-05-26

Objective audited: implement `docs/implementation-plan.md`.

## Summary

The bridge, adapter boundary, KOReader plugin modules, mock flow, and real
`nlm` EPUB bridge flow are implemented and locally verified.

The remaining unproven item is runtime behavior inside real KOReader on a
device, emulator, or desktop build. No runnable macOS KOReader build was present
locally during this audit; only Kindle ARM bundles were found, which cannot run
on this Mac.

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
- link-existing notebook picker flow
- create-notebook flow
- multipart upload flow
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
| Bridge URL and settings are configurable | Done | `settings.lua`; `NotebookLM -> Bridge URL` |
| Source upload feature flag | Done, stub-verified | `settings.lua`; Lua verifier checks hidden setup upload action and disabled upload error |
| Book id is derived and link metadata stored locally | Done | `storage.lua`; Lua verifier exercises persistence |
| Bridge stores book-to-notebook mapping | Done | `/books/link`; pytest and smoke flow |
| Link existing notebook | Done, stub-verified | `ui.lua` notebook picker; Lua verifier invokes picker callback and checks saved link |
| Create notebook | Done | `/notebooks`; Lua verifier and smoke scripts |
| Create notebook and upload source | Done | `ui.lua`; `/sources/upload-file`; Lua verifier; real EPUB smoke |
| Highlight menu actions | Implemented, stub-verified | `main.lua`; Lua verifier executes highlight-menu callbacks |
| Preset prompts | Done | `prompts.lua`; `main.lua` prompt buttons |
| Custom question | Done, stub-verified | `ui.lua` custom dialog; Lua verifier invokes custom ask callback |
| Ask bridge endpoint | Done | `/ask`; pytest; mock and real smoke; Lua verifier checks selected text, prompt, notebook id, and book context payload |
| Scrollable answer view | Done, stub-verified | `TextViewer.openFile`; Lua verifier checks answer, long selected text, long answer text, source, reference, and citation output |
| Offline bridge error display | Done, stub-verified | Lua verifier forces network error and checks status dialog text |
| Multipart upload for device-to-bridge | Done | `/sources/upload-file`; pytest; mock and real smoke |
| Real EPUB accepted by `nlm` path | Done | `scripts/smoke-real-epub.sh` run on 2026-05-26 |
| KOReader real device/emulator runtime | Not proven | No runnable local KOReader environment available |
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

3. In KOReader, set:

   ```text
   NotebookLM -> Bridge URL -> http://<mac-lan-ip>:8765
   ```

4. Open a book.
5. Confirm `NotebookLM -> Status` shows bridge OK.
6. Run `NotebookLM -> Current book setup`.
7. Create a notebook in mock mode.
8. Reopen setup and confirm the book remains linked.
9. Highlight text.
10. Tap `Ask NotebookLM`.
11. Send a custom question.
12. Confirm answer opens in KOReader.
13. Highlight text again.
14. Tap a preset prompt such as `Explica simple (NotebookLM)`.
15. Confirm answer opens in KOReader.
16. Stop bridge and confirm plugin shows a readable bridge error.
17. Inspect KOReader logs for stack traces.

After mock mode passes, repeat with:

```sh
KOREADER_NOTEBOOKLM_ADAPTER=nlm KOREADER_NOTEBOOKLM_HOST=0.0.0.0 scripts/run-bridge-dev.sh
```

Acceptance requires no Lua stack traces, successful link persistence, successful
ask flow, and readable answer display.
