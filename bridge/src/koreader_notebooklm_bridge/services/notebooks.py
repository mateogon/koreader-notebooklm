"""Notebook service."""

from ..adapters.base import NotebookLMAdapter
from ..models import NotebookCreateResponse, NotebookSummary


def list_notebooks(adapter: NotebookLMAdapter) -> list[NotebookSummary]:
    return adapter.list_notebooks()


def create_notebook(adapter: NotebookLMAdapter, title: str) -> NotebookCreateResponse:
    return adapter.create_notebook(title)
