"""Book mapping routes."""

import logging

from fastapi import APIRouter, Depends, HTTPException

from ..models import BookLinkRequest, BookLinkResponse
from ..services.books import delete_book, get_book, link_book
from ..store import BookMappingStore
from .dependencies import get_book_store

router = APIRouter()
logger = logging.getLogger("uvicorn.error")


@router.get("/books/{book_id}", response_model=BookLinkResponse)
def get_book_mapping(
    book_id: str,
    store: BookMappingStore = Depends(get_book_store),
) -> BookLinkResponse:
    book = get_book(store, book_id)
    if book is None:
        logger.info("Bridge book mapping miss book_id=%s", book_id)
        raise HTTPException(status_code=404, detail="Book mapping not found.")
    logger.info("Bridge book mapping hit book_id=%s notebook_id=%s", book_id, book.notebook_id)
    return BookLinkResponse(book=book)


@router.post("/books/link", response_model=BookLinkResponse)
def post_book_link(
    request: BookLinkRequest,
    store: BookMappingStore = Depends(get_book_store),
) -> BookLinkResponse:
    logger.info("Bridge book link saved book_id=%s notebook_id=%s", request.book_id, request.notebook_id)
    return BookLinkResponse(book=link_book(store, request))


@router.delete("/books/{book_id}")
def delete_book_mapping(
    book_id: str,
    store: BookMappingStore = Depends(get_book_store),
) -> dict[str, bool]:
    existed = delete_book(store, book_id)
    logger.info("Bridge book mapping delete book_id=%s existed=%s", book_id, existed)
    return {"ok": True, "deleted": existed}
