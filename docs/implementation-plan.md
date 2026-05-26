# Implementation Plan

This plan starts from the current bridge-first architecture:

```text
KOReader plugin -> local HTTP bridge -> NotebookLM adapter
```

The plugin should be useful but boring: it owns KOReader UI, book metadata, and
user actions. The bridge owns NotebookLM operations and authentication-adjacent
behavior through the current `nlm` adapter.

## Design Rule

The KOReader UI must not call bridge HTTP directly. It should call a small
NotebookLM client interface that can later be backed by a different transport.

Initial implementation:

```text
ui.lua/main.lua -> client.lua -> http.lua -> local bridge
```

Future all-in-Kindle implementation:

```text
ui.lua/main.lua -> client.lua -> kindle/internal adapter
```

As long as `client.lua` returns the same Lua tables, the UI should not care
whether the work happens through the Mac bridge, Termux, a small local server,
or a future internal Kindle path.

## Target User Flow

### First Open For A Book

1. KOReader opens a book.
2. The plugin derives a stable `book_id`.
3. The plugin checks local per-book metadata for `notebook_id`.
4. If no notebook is linked, the plugin offers:
   - link an existing NotebookLM notebook
   - create a new NotebookLM notebook
   - create a new notebook and upload the book source
   - skip setup for now
5. The chosen `notebook_id` is stored locally for that book.
6. The bridge also stores the same book-to-notebook mapping.

### Reading And Asking

1. The user highlights text.
2. The highlight menu shows NotebookLM actions.
3. The user chooses either a prompt preset or a custom question.
4. The plugin sends selected text, prompt, book context, and `notebook_id` to
   the client.
5. The client calls the bridge.
6. KOReader shows a loading state.
7. The plugin displays the response in a readable answer view.

## Plugin Module Plan

### `main.lua`

Responsibilities:
- plugin entrypoint
- register highlight-menu actions
- register a Tools-menu entry for setup/status
- route user actions to `ui.lua`

Reference files:
- `vendor-references/AskGPT/main.lua`
- `vendor-references/assistant.koplugin/main.lua`

### `client.lua`

New file to add.

Responsibilities:
- high-level NotebookLM client interface
- expose methods:
  - `health()`
  - `list_notebooks()`
  - `create_notebook(title)`
  - `get_book(book_id)`
  - `link_book(book)`
  - `upload_source(notebook_id, source)`
  - `ask(request)`
- hide whether the backend is HTTP, local, or future internal Kindle logic

This is the main portability boundary.

### `http.lua`

Responsibilities:
- low-level HTTP transport only
- JSON encode/decode
- GET/POST helpers
- timeout/error normalization

No UI and no book-specific logic should live here.

### `settings.lua`

Responsibilities:
- bridge URL
- timeout defaults
- feature flags for source upload and prompt buttons
- possible future backend mode:
  - `bridge`
  - `internal`

### `storage.lua`

Responsibilities:
- derive `book_id`
- read/write per-book NotebookLM metadata:
  - `book_id`
  - `notebook_id`
  - `notebook_title`
  - `source_id`
  - `linked_at`
- prefer KOReader per-book settings when available
- fall back to plugin settings if needed

The bridge should also keep a copy of the mapping, but KOReader needs local
metadata so the current book can behave correctly even before a bridge lookup.

### `ui.lua`

Responsibilities:
- setup/status dialog for current book
- notebook picker
- create-notebook dialog
- upload confirmation
- prompt picker
- loading message
- answer viewer
- error dialogs

Reference files:
- `vendor-references/AskGPT/dialogs.lua`
- `vendor-references/assistant.koplugin/assistant_dialog.lua`
- `vendor-references/assistant.koplugin/assistant_settings.lua`

### `prompts.lua`

Responsibilities:
- preset prompt definitions
- prompt labels for the highlight menu
- prompt text sent to NotebookLM

Initial presets:
- Explain this passage simply.
- Explain why this passage matters.
- Give the book context for this passage.
- Summarize this passage in three bullets.
- Clarify this sentence or term.
- Custom question.

### Response Viewer

Start simple, then improve.

Phase 1:
- use a KOReader text dialog/viewer that can scroll
- show answer text plus basic citations/references if returned

Phase 2:
- render lightweight Markdown
- evaluate the `assistant.koplugin` markdown/viewer approach
- keep renderer behind `ui.lua`, not inside `client.lua`

## Bridge API Use

Existing useful endpoints:

```http
GET /health
GET /notebooks
POST /notebooks
GET /books/{book_id}
POST /books/link
POST /sources/upload
POST /ask
```

### Link Existing Notebook

```text
GET /notebooks
POST /books/link
storage.lua saves local metadata
```

### Create Notebook

```text
POST /notebooks
POST /books/link
storage.lua saves local metadata
```

### Create Notebook And Upload Book

Current bridge support accepts a bridge-local `file_path`. That is enough for
Mac-side testing, but it is not enough for a physical Kindle unless the Mac can
see the same file path.

Implementation path:

1. Validate which source formats `nlm` accepts reliably, including EPUB.
2. Keep JSON `file_path` upload for local Mac smoke tests.
3. Add multipart upload support for KOReader device-to-bridge transfer.
4. After upload succeeds, call `POST /books/link` with `source_id`.

The plugin should call only `client:upload_source(...)`, so this transport
change does not affect UI code.

### Ask

```text
POST /ask
```

Request data from plugin:

```json
{
  "notebook_id": "linked-notebook-id",
  "selected_text": "Highlighted text",
  "prompt": "Explain this passage simply.",
  "book": {
    "title": "Book title",
    "author": "Author",
    "path": "/path/on/device/book.epub",
    "position": "optional page/progress"
  }
}
```

## Implementation Phases

### Phase 0 - Reference Audit

Inspect the local reference plugins in detail:
- `AskGPT`: minimal highlight flow, HTTP call, result viewer
- `assistant.koplugin`: settings, richer dialogs, prompt buttons, viewer

Output:
- update `research/koreader-plugin-notes.md` with exact KOReader APIs we will
  use
- identify the safest JSON module for KOReader devices
- identify the simplest scrollable response viewer

### Phase 1 - Plugin Client Boundary

Add `client.lua` and turn placeholder modules into real modules with no
NotebookLM behavior yet.

Output:
- settings load default bridge URL
- `client:health()` calls bridge through `http.lua`
- Tools-menu action can show bridge health/status
- no highlight workflow yet

### Phase 2 - Book Link Setup

Implement current-book metadata and notebook linking.

Output:
- derive and display current `book_id`
- fetch existing link from local storage and bridge
- list notebooks from bridge
- create notebook from KOReader
- link current book to selected/created notebook
- persist mapping locally and in bridge

### Phase 3 - Source Upload Setup

Implement create-and-upload flow.

Output:
- local Mac `file_path` upload works first
- multipart/device upload is added after local upload is stable
- source id is stored with book metadata
- EPUB support is validated instead of assumed

### Phase 4 - Highlight Ask Flow

Implement the core reading interaction.

Output:
- highlight menu shows NotebookLM action
- if book is unlinked, setup dialog opens first
- preset prompts can ask immediately
- custom question opens input dialog
- selected text and book context are sent to `/ask`

### Phase 5 - Answer Viewer

Implement a usable response view.

Output:
- loading state while waiting
- scrollable answer view
- answer can include simple sections:
  - question/prompt
  - selected passage
  - NotebookLM answer
  - references/citations when available
- lightweight Markdown rendering is evaluated after plain text works

### Phase 6 - Install And Debug Loop

Document the development workflow.

Output:
- copy/symlink plugin into KOReader plugins directory
- run bridge in mock mode
- run bridge in `nlm` mode
- test health, link, create, upload, and ask from KOReader
- collect KOReader log locations and common errors

### Phase 7 - Portability Pass

Prepare for mobile/Termux and future all-in-Kindle.

Output:
- no hardcoded Mac-only paths in plugin
- bridge URL can point to LAN IP
- `client.lua` is the only backend boundary used by UI
- internal backend remains possible without rewriting dialogs

## Testing Strategy

Bridge:
- keep pytest coverage for all endpoint contracts
- add tests for multipart upload when implemented
- keep mock adapter deterministic

Plugin:
- start with manual KOReader testing
- test in mock bridge mode before real `nlm`
- verify unlinked book flow
- verify linked book flow
- verify bridge offline/error states
- verify long selected text and long answer rendering

## Near-Term Definition Of Done

The next useful milestone is complete when:

1. KOReader can link the current book to a NotebookLM notebook.
2. The link is remembered for that book.
3. A highlighted passage can be sent to the bridge with a preset prompt.
4. A custom question can be sent for the same highlighted passage.
5. The answer is readable inside KOReader.
6. UI code depends on `client.lua`, not directly on HTTP details.
