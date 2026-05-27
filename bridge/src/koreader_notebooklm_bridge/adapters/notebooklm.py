"""NotebookLM adapter backed by the local `nlm` CLI.

The bridge does not copy or parse NotebookLM auth files. The `nlm` command
loads its own configured profile from the user's normal NotebookLM MCP/CLI
storage.
"""

from __future__ import annotations

import json
import logging
import subprocess
from typing import Any

from ..config import BridgeConfig
from ..models import (
    AskRequest,
    AskResponse,
    NotebookCreateResponse,
    NotebookSummary,
    SourceUploadRequest,
    SourceUploadResponse,
)
from .errors import AdapterCommandError, AdapterNotConfiguredError

logger = logging.getLogger("uvicorn.error")


class NlmNotebookLMAdapter:
    name = "nlm"

    def __init__(self, config: BridgeConfig):
        self.config = config

    def list_notebooks(self) -> list[NotebookSummary]:
        data = self._run_json(self._with_profile(["notebook", "list", "--json"]))
        if not isinstance(data, list):
            raise AdapterCommandError("Unexpected `nlm notebook list --json` response.")

        notebooks: list[NotebookSummary] = []
        for item in data:
            if not isinstance(item, dict):
                continue
            notebook_id = item.get("id")
            title = item.get("title") or "Untitled"
            if isinstance(notebook_id, str):
                notebooks.append(
                    NotebookSummary(
                        id=notebook_id,
                        title=str(title),
                        source_count=int(item.get("source_count") or 0),
                    )
                )
        return notebooks

    def ask(self, request: AskRequest) -> AskResponse:
        notebook_id = request.notebook_id or self.config.default_notebook_id
        if not notebook_id:
            raise AdapterNotConfiguredError(
                "No notebook_id was provided and no default notebook is configured."
            )

        logger.info(
            "NotebookLM nlm ask notebook_id=%s selected_chars=%s prompt_chars=%s",
            notebook_id,
            len(request.selected_text or ""),
            len(request.prompt or ""),
        )
        question = self._build_question(request)
        args = [
            "notebook",
            "query",
            "--json",
            "--timeout",
            str(self.config.nlm_timeout_seconds),
        ]
        if request.conversation_id:
            args.extend(["--conversation-id", request.conversation_id])
        args.extend([notebook_id, question])
        data = self._run_json(
            self._with_profile(args),
            timeout=self.config.nlm_timeout_seconds + 10,
        )
        if not isinstance(data, dict):
            raise AdapterCommandError("Unexpected `nlm notebook query --json` response.")
        if isinstance(data.get("value"), dict):
            data = data["value"]

        answer = data.get("answer")
        if not isinstance(answer, str) or not answer.strip():
            raise AdapterCommandError("NotebookLM returned an empty answer.")

        return AskResponse(
            answer=answer,
            notebook_id=notebook_id,
            adapter=self.name,
            conversation_id=_optional_str(data.get("conversation_id")),
            sources_used=_string_list(data.get("sources_used")),
            citations=data.get("citations") if isinstance(data.get("citations"), dict) else {},
            references=data.get("references") if isinstance(data.get("references"), list) else [],
        )

    def create_notebook(self, title: str) -> NotebookCreateResponse:
        completed = self._run_text(self._with_profile(["notebook", "create", title]))
        notebook_id = _extract_id_line(completed)
        if not notebook_id:
            raise AdapterCommandError("Could not find created notebook ID in `nlm` output.")
        notebook = NotebookSummary(id=notebook_id, title=title or "Untitled notebook", source_count=0)
        return NotebookCreateResponse(
            notebook=notebook,
            url=f"https://notebooklm.google.com/notebook/{notebook_id}",
            adapter=self.name,
        )

    def upload_source(self, request: SourceUploadRequest) -> SourceUploadResponse:
        before_sources = self._list_sources(request.notebook_id)
        before_ids = {source["id"] for source in before_sources if isinstance(source.get("id"), str)}
        args = [
            "source",
            "add",
            request.notebook_id,
            "--file",
            request.file_path,
        ]
        if request.title:
            args.extend(["--title", request.title])
        if request.wait:
            args.append("--wait")
        data = self._run_text(self._with_profile(args), timeout=self.config.nlm_timeout_seconds + 30)
        source_id = _extract_id_line(data)
        source_title = request.title or request.file_path.rsplit("/", 1)[-1]
        if not source_id:
            after_sources = self._list_sources(request.notebook_id)
            new_sources = [
                source
                for source in after_sources
                if isinstance(source.get("id"), str) and source["id"] not in before_ids
            ]
            if new_sources:
                source_id = str(new_sources[0]["id"])
                if isinstance(new_sources[0].get("title"), str):
                    source_title = str(new_sources[0]["title"])
        if not source_id:
            raise AdapterCommandError("Could not find uploaded source ID in `nlm` output.")
        return SourceUploadResponse(
            source_id=source_id,
            title=source_title,
            notebook_id=request.notebook_id,
            adapter=self.name,
        )

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

    def _run_json(self, args: list[str], timeout: float | None = None) -> Any:
        output = self._run_text(args, timeout=timeout)
        try:
            return json.loads(output)
        except json.JSONDecodeError as e:
            raise AdapterCommandError(
                "Could not parse `nlm` JSON output: " + _truncate_error(output)
            ) from e

    def _run_text(self, args: list[str], timeout: float | None = None) -> str:
        command = [self.config.nlm_command, *args]
        logger.info("NotebookLM running command: %s", " ".join(_safe_args(command)))
        try:
            completed = subprocess.run(
                command,
                capture_output=True,
                check=False,
                text=True,
                timeout=timeout or self.config.nlm_timeout_seconds,
            )
        except FileNotFoundError as e:
            raise AdapterCommandError(
                f"`{self.config.nlm_command}` was not found. Install notebooklm-mcp-cli or set KOREADER_NOTEBOOKLM_NLM_COMMAND."
            ) from e
        except subprocess.TimeoutExpired as e:
            raise AdapterCommandError(f"`nlm` timed out after {e.timeout} seconds.") from e

        if completed.returncode != 0:
            message = (completed.stderr or completed.stdout or "Unknown nlm error").strip()
            logger.warning(
                "NotebookLM nlm command failed returncode=%s stderr_or_stdout=%s",
                completed.returncode,
                _truncate_error(message, limit=300),
            )
            raise AdapterCommandError(_truncate_error(message))
        return completed.stdout

    def _with_profile(self, args: list[str]) -> list[str]:
        if not self.config.nlm_profile:
            return args
        return [*args, "--profile", self.config.nlm_profile]

    def _list_sources(self, notebook_id: str) -> list[dict[str, object]]:
        data = self._run_json(self._with_profile(["source", "list", notebook_id, "--json"]))
        if not isinstance(data, list):
            raise AdapterCommandError("Unexpected `nlm source list --json` response.")
        return [item for item in data if isinstance(item, dict)]


def _optional_str(value: object) -> str | None:
    return value if isinstance(value, str) else None


def _string_list(value: object) -> list[str]:
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, str)]


def _truncate_error(value: str, limit: int = 800) -> str:
    value = value.strip()
    if len(value) <= limit:
        return value
    return value[:limit] + "..."


def _safe_args(command: list[str]) -> list[str]:
    safe = list(command)
    if "query" in safe and safe:
        safe[-1] = f"<question chars={len(safe[-1])}>"
    return safe


def _extract_id_line(output: str) -> str | None:
    for line in output.splitlines():
        stripped = line.strip()
        if "Source ID:" in stripped:
            return stripped.split("Source ID:", 1)[1].strip()
        if stripped.startswith("ID:"):
            return stripped.split("ID:", 1)[1].strip()
        if len(stripped) >= 30 and "-" in stripped and " " not in stripped:
            return stripped
    return None
