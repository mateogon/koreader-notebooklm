# MVP Plan

This plan comes from the initial planning chat and is intentionally concrete enough to guide the first implementation passes.

## MVP Decision

Start with:

```text
KOReader Lua plugin -> local HTTP bridge on Mac -> NotebookLM adapter
```

Keep the all-in-Kindle path open, but treat it as a later experiment. The first usable version should not depend on NotebookLM running directly on the Kindle.

## MVP Goal

The first useful MVP should do only this:

1. A NotebookLM notebook already exists and already contains the book or source.
2. The user selects text in KOReader.
3. The user taps `Ask NotebookLM`.
4. The user chooses or enters a prompt.
5. KOReader sends `selected_text` and prompt data to the bridge.
6. The bridge asks a fixed NotebookLM notebook.
7. KOReader displays the response.

This validates the core reading experience without mixing in automatic book upload, notebook creation, Kindle auth, or mobile deployment.

## Starting Stack

For the Mac bridge:

- Python 3.11+
- `uv` or `venv`
- FastAPI
- Uvicorn
- SQLite later, for book-to-notebook mapping
- `notebooklm-mcp-cli` later, likely through `nlm` subprocess first

For future mobile portability:

- Keep HTTP plain and local-network friendly.
- Use `.env` or config files instead of hardcoded Mac paths.
- Avoid Docker as a requirement.
- Avoid unusual native dependencies.
- Keep the bridge runnable outside macOS if possible.

## Milestones

### Hito 0 - NotebookLM smoke test on Mac

Expected result:

```text
nlm login works
nlm notebook list works
nlm notebook query works
```

If this does not work on Mac, do not continue into KOReader integration yet.

### Hito 1 - Dummy bridge

Expected result:

```text
GET /health returns OK
POST /ask returns fake text
curl works from another device on the same network
```

### Hito 2 - Real bridge with fixed notebook

Expected result:

```text
POST /ask -> nlm notebook query -> real NotebookLM response
```

Use `nlm` by subprocess first. It is less elegant than importing internals, but it reduces early uncertainty and avoids coupling this bridge to private Python APIs before the local HTTP contract is proven.

Initial adapter commands:

```bash
nlm notebook list --json
nlm notebook query --json --timeout 120 <NOTEBOOK_ID> "<QUESTION>"
```

After the bridge contract is stable, revisit a direct Python adapter using `notebooklm_tools.services`.

### Hito 3 - KOReader plugin with fixed notebook

Expected result:

```text
selected passage in KOReader -> bridge -> NotebookLM -> visible response in KOReader
```

### Hito 4 - Book-to-notebook mapping

Expected result:

```text
each book remembers its notebook_id
```

Store this in the bridge first, probably SQLite.

### Hito 5 - Create or link notebook from KOReader

Expected result:

```text
if no notebook is linked, KOReader offers to use default, link existing, or create new
```

### Hito 6 - Source upload

Expected result:

```text
KOReader or the bridge can upload the book/source to NotebookLM
```

Start with PDF. EPUB/AZW3/KFX support must be validated instead of assumed.

## Initial API Shape

Start with:

```http
GET /health
GET /notebooks
POST /ask
```

Then add:

```http
POST /notebooks
GET /books/{book_id}
POST /books/link
POST /sources/upload
```

Initial `POST /ask` request:

```json
{
  "notebook_id": "abc123",
  "selected_text": "Selected passage from the book.",
  "prompt": "Explain this passage simply.",
  "book": {
    "title": "Book title",
    "author": "Author",
    "path": "/mnt/us/documents/book.epub",
    "position": "chapter 2 / 34%"
  }
}
```

Initial response:

```json
{
  "ok": true,
  "answer": "NotebookLM response.",
  "notebook_id": "abc123"
}
```

## KOReader MVP UX

The plugin should do only this at first:

```text
read bridge_url
read default_notebook_id
capture selected_text
show "Ask NotebookLM" in the highlight menu
send POST /ask
show response in a scrollable view
```

Initial prompt options:

- Explain this passage simply.
- Give context for this passage inside the book.
- Why is this passage important?
- Summarize this passage in 3 bullets.
- Custom question.

## Deferred Work

- NotebookLM authentication strategy.
- Direct Python adapter instead of `nlm` subprocess.
- Automatic notebook creation.
- Automatic source upload.
- Book format conversion or text extraction.
- Android/Termux bridge support.
- All-in-Kindle client.
- MCP.
