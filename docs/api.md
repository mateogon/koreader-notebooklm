# Bridge API

These endpoints are implemented in the local bridge. In `mock` mode they return deterministic fake data. In `nlm` mode, NotebookLM operations are delegated to the local `nlm` CLI and its existing auth profile.

- `GET /health`
- `GET /notebooks`
- `POST /notebooks`
- `GET /books/{book_id}`
- `POST /books/link`
- `POST /sources/upload`
- `POST /sources/upload-file`
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

## `POST /books/link`

Request:

```json
{
  "book_id": "book-stable-id",
  "notebook_id": "notebook-id",
  "notebook_title": "Notebook title",
  "title": "Book title",
  "author": "Author",
  "path": "/mnt/us/documents/book.epub",
  "source_id": "source-id",
  "linked_at": "2026-05-26T00:00:00Z"
}
```

Response:

```json
{
  "ok": true,
  "book": {
    "book_id": "book-stable-id",
    "notebook_id": "notebook-id",
    "notebook_title": "Notebook title",
    "title": "Book title",
    "author": "Author",
    "path": "/mnt/us/documents/book.epub",
    "source_id": "source-id",
    "linked_at": "2026-05-26T00:00:00Z"
  }
}
```

## `POST /sources/upload`

JSON upload for files already visible to the bridge host.

Request:

```json
{
  "notebook_id": "notebook-id",
  "file_path": "/Users/me/book.epub",
  "title": "Book title",
  "wait": true
}
```

## `POST /sources/upload-file`

Multipart upload for KOReader devices sending the book file to the bridge.

Form fields:

- `notebook_id`
- `title`
- `wait`
- `file`

The bridge stores the uploaded file under its local data directory, then passes
that saved path to the active NotebookLM adapter.

## Auth

The bridge never stores NotebookLM credentials. Real mode shells out to `nlm`, which reads its own auth/profile state.
