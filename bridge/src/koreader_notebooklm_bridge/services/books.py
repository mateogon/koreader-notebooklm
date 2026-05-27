"""Book mapping service."""

from ..models import BookLinkRequest
from ..store import BookMappingStore


def get_book(store: BookMappingStore, book_id: str) -> BookLinkRequest | None:
    return store.get(book_id)


def link_book(store: BookMappingStore, request: BookLinkRequest) -> BookLinkRequest:
    return store.put(request)


def delete_book(store: BookMappingStore, book_id: str) -> bool:
    return store.delete(book_id)
