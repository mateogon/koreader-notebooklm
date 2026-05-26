# Bridge API

These endpoints are implemented in the local bridge. In `mock` mode they return deterministic fake data. In `nlm` mode, NotebookLM operations are delegated to the local `nlm` CLI and its existing auth profile.

- `GET /health`
- `GET /notebooks`
- `POST /notebooks`
- `GET /books/{book_id}`
- `POST /books/link`
- `POST /sources/upload`
- `POST /ask`

## `POST /ask`

Request:

```json
{
  "notebook_id": "notebook-id",
  "selected_text": "Selected passage.",
  "prompt": "Explain this simply.",
  "book": {
    "title": "Book title",
    "author": "Author",
    "path": "/mnt/us/documents/book.epub",
    "position": "chapter 1 / 10%"
  }
}
```

If `notebook_id` is omitted, real mode uses `KOREADER_NOTEBOOKLM_DEFAULT_NOTEBOOK_ID`.

Response:

```json
{
  "ok": true,
  "answer": "Answer text.",
  "notebook_id": "notebook-id",
  "adapter": "nlm",
  "conversation_id": "optional-conversation-id",
  "sources_used": [],
  "citations": {},
  "references": []
}
```

## Auth

The bridge never stores NotebookLM credentials. Real mode shells out to `nlm`, which reads its own auth/profile state.
