"""FastAPI route dependencies."""

from fastapi import Request

from ..adapters.base import NotebookLMAdapter
from ..config import BridgeConfig
from ..store import BookMappingStore


def get_config(request: Request) -> BridgeConfig:
    return request.app.state.config


def get_adapter(request: Request) -> NotebookLMAdapter:
    return request.app.state.adapter


def get_book_store(request: Request) -> BookMappingStore:
    return request.app.state.book_store
