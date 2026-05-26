"""Adapter boundary for NotebookLM-like integrations."""

from typing import Protocol

from ..models import (
    AskRequest,
    AskResponse,
    NotebookCreateResponse,
    NotebookSummary,
    SourceUploadRequest,
    SourceUploadResponse,
)


class NotebookLMAdapter(Protocol):
    """Interface used by bridge services.

    Implementations may be mock, subprocess-backed, or direct Python adapters.
    """

    name: str

    def list_notebooks(self) -> list[NotebookSummary]:
        """Return notebooks available to the bridge."""

    def ask(self, request: AskRequest) -> AskResponse:
        """Ask a notebook about selected text."""

    def create_notebook(self, title: str) -> NotebookCreateResponse:
        """Create a new notebook."""

    def upload_source(self, request: SourceUploadRequest) -> SourceUploadResponse:
        """Upload or add a source to a notebook."""
