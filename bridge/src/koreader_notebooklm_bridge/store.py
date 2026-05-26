"""Local persistence for book-to-notebook mapping."""

from __future__ import annotations

import json
from pathlib import Path

from .models import BookLinkRequest


class BookMappingStore:
    def __init__(self, data_dir: Path):
        self.path = data_dir / "books.json"

    def get(self, book_id: str) -> BookLinkRequest | None:
        data = self._read()
        item = data.get(book_id)
        if not isinstance(item, dict):
            return None
        return BookLinkRequest.model_validate(item)

    def put(self, request: BookLinkRequest) -> BookLinkRequest:
        data = self._read()
        data[request.book_id] = request.model_dump()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        return request

    def _read(self) -> dict[str, object]:
        if not self.path.exists():
            return {}
        return json.loads(self.path.read_text())
