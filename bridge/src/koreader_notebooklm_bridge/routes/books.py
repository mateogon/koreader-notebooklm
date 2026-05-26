"""Book mapping routes."""

from fastapi import APIRouter, Depends, HTTPException

from ..models import BookLinkRequest, BookLinkResponse
from ..services.books import get_book, link_book
from ..store import BookMappingStore
from .dependencies import get_book_store

router = APIRouter()


@router.get("/books/{book_id}", response_model=BookLinkResponse)
def get_book_mapping(
    book_id: str,
    store: BookMappingStore = Depends(get_book_store),
) -> BookLinkResponse:
    book = get_book(store, book_id)
    if book is None:
        raise HTTPException(status_code=404, detail="Book mapping not found.")
    return BookLinkResponse(book=book)


@router.post("/books/link", response_model=BookLinkResponse)
def post_book_link(
    request: BookLinkRequest,
    store: BookMappingStore = Depends(get_book_store),
) -> BookLinkResponse:
    return BookLinkResponse(book=link_book(store, request))
