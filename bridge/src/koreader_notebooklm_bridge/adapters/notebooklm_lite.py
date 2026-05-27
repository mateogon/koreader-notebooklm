"""NotebookLM adapter backed by a small direct HTTP client.

This adapter intentionally does not import `notebooklm_tools` and does not call
the `nlm` subprocess. It reads existing auth state and talks to NotebookLM's
private web RPCs directly.
"""

from __future__ import annotations

import logging

from ..config import BridgeConfig
from ..models import (
    AskRequest,
    AskResponse,
    NotebookCreateResponse,
    NotebookSummary,
    SourceUploadRequest,
    SourceUploadResponse,
)
from ..notebooklm_lite import NotebookLMLiteClient, load_auth_bundle
from ..notebooklm_lite.errors import NotebookLMLiteError
from .errors import AdapterCommandError, AdapterNotConfiguredError

logger = logging.getLogger("uvicorn.error")


class NlmLiteNotebookLMAdapter:
    name = "nlm-lite"

    def __init__(self, config: BridgeConfig):
        self.config = config
        self._client: NotebookLMLiteClient | None = None

    def list_notebooks(self) -> list[NotebookSummary]:
        try:
            notebooks = self._get_client().list_notebooks()
        except NotebookLMLiteError as e:
            raise _adapter_error(e) from e
        return [
            NotebookSummary(
                id=str(item["id"]),
                title=str(item.get("title") or "Untitled"),
                source_count=int(item.get("source_count") or 0),
            )
            for item in notebooks
            if isinstance(item.get("id"), str)
        ]

    def ask(self, request: AskRequest) -> AskResponse:
        notebook_id = request.notebook_id or self.config.default_notebook_id
        if not notebook_id:
            raise AdapterNotConfiguredError(
                "No notebook_id was provided and no default notebook is configured."
            )

        logger.info(
            "NotebookLM nlm-lite ask notebook_id=%s selected_chars=%s prompt_chars=%s",
            notebook_id,
            len(request.selected_text or ""),
            len(request.prompt or ""),
        )
        try:
            result = self._get_client().ask(
                notebook_id=notebook_id,
                question=self._build_question(request),
                conversation_id=request.conversation_id,
            )
        except NotebookLMLiteError as e:
            raise _adapter_error(e) from e

        answer = result.get("answer")
        if not isinstance(answer, str) or not answer.strip():
            raise AdapterCommandError("NotebookLM returned an empty answer.")
        return AskResponse(
            answer=answer,
            notebook_id=notebook_id,
            adapter=self.name,
            conversation_id=_optional_str(result.get("conversation_id")),
            sources_used=_string_list(result.get("sources_used")),
            citations=result.get("citations") if isinstance(result.get("citations"), dict) else {},
            references=result.get("references") if isinstance(result.get("references"), list) else [],
        )

    def create_notebook(self, title: str) -> NotebookCreateResponse:
        try:
            item = self._get_client().create_notebook(title)
        except NotebookLMLiteError as e:
            raise _adapter_error(e) from e
        notebook_id = str(item["id"])
        notebook = NotebookSummary(
            id=notebook_id,
            title=str(item.get("title") or title or "Untitled notebook"),
            source_count=int(item.get("source_count") or 0),
        )
        return NotebookCreateResponse(
            notebook=notebook,
            url=f"{self.config.notebooklm_base_url}/notebook/{notebook_id}",
            adapter=self.name,
        )

    def upload_source(self, request: SourceUploadRequest) -> SourceUploadResponse:
        try:
            result = self._get_client().upload_file(
                notebook_id=request.notebook_id,
                file_path=request.file_path,
                title=request.title,
                wait=request.wait,
            )
        except NotebookLMLiteError as e:
            raise _adapter_error(e) from e

        source_id = result.get("id")
        if not isinstance(source_id, str):
            raise AdapterCommandError("Could not find uploaded source ID in NotebookLM response.")
        return SourceUploadResponse(
            source_id=source_id,
            title=str(result.get("title") or request.title or request.file_path.rsplit("/", 1)[-1]),
            notebook_id=request.notebook_id,
            adapter=self.name,
        )

    def _get_client(self) -> NotebookLMLiteClient:
        if self._client is None:
            try:
                auth = load_auth_bundle(
                    bundle_path=self.config.auth_bundle_path,
                    profile=self.config.nlm_profile,
                    base_url=self.config.notebooklm_base_url,
                )
                client = NotebookLMLiteClient(
                    auth,
                    timeout=self.config.direct_timeout_seconds,
                    upload_wait_seconds=self.config.upload_wait_seconds,
                )
                if not auth.csrf_token:
                    client.refresh_auth()
                self._client = client
            except NotebookLMLiteError as e:
                raise _adapter_error(e) from e
        return self._client

    def _build_question(self, request: AskRequest) -> str:
        parts = [request.prompt.strip()]
        if request.book:
            book_lines = []
            if request.book.title:
                book_lines.append(f"Title: {request.book.title}")
            if request.book.author:
                book_lines.append(f"Author: {request.book.author}")
            if request.book.position:
                book_lines.append(f"Position: {request.book.position}")
            if book_lines:
                parts.append("Book context:\n" + "\n".join(book_lines))
        parts.append(f'Selected passage:\n"""\n{request.selected_text.strip()}\n"""')
        return "\n\n".join(parts)


def _adapter_error(error: NotebookLMLiteError) -> AdapterCommandError:
    return AdapterCommandError(f"{error.info.kind}: {error.info.message}")


def _optional_str(value: object) -> str | None:
    return value if isinstance(value, str) else None


def _string_list(value: object) -> list[str]:
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, str)]
