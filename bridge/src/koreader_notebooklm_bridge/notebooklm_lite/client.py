"""Direct NotebookLM HTTP client for the experimental nlm-lite adapter."""

from __future__ import annotations

from pathlib import Path
import time
from typing import Any
from uuid import uuid4

import httpx

from .auth import AuthBundle, refresh_page_tokens, to_httpx_cookies
from .errors import NotebookLMProtocolError, NotebookLMRequestError
from .parsing import (
    extract_source_ids,
    parse_batchexecute_response,
    parse_notebooks,
    parse_query_response,
    parse_sources_from_notebook_data,
)
from .rpc import (
    RPC_ADD_SOURCE_FILE,
    RPC_CREATE_NOTEBOOK,
    RPC_GET_CONVERSATIONS,
    RPC_GET_NOTEBOOK,
    RPC_LIST_NOTEBOOKS,
    RPC_RENAME_SOURCE,
    RequestIds,
    build_batchexecute_body,
    build_batchexecute_url,
    build_query_body,
    build_query_url,
)

UNKNOWN_SOURCE_ERROR_GRACE_SECONDS = 90.0


class NotebookLMLiteClient:
    def __init__(
        self,
        auth: AuthBundle,
        *,
        timeout: float = 120.0,
        upload_wait_seconds: float = 600.0,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        self.auth = auth
        self.timeout = timeout
        self.upload_wait_seconds = upload_wait_seconds
        self._request_ids = RequestIds()
        self._transport = transport
        self._conversation_cache: dict[str, list[tuple[str, str]]] = {}

    def refresh_auth(self) -> None:
        self.auth = refresh_page_tokens(
            self.auth,
            timeout=min(15.0, self.timeout),
            transport=self._transport,
        )

    def list_notebooks(self) -> list[dict[str, Any]]:
        result = self._call_rpc(RPC_LIST_NOTEBOOKS, [None, 1, None, [2]])
        return parse_notebooks(result)

    def get_notebook(self, notebook_id: str) -> Any:
        return self._call_rpc(
            RPC_GET_NOTEBOOK,
            [notebook_id, None, [2], None, 0],
            source_path=f"/notebook/{notebook_id}",
        )

    def create_notebook(self, title: str) -> dict[str, Any]:
        result = self._call_rpc(
            RPC_CREATE_NOTEBOOK,
            [title, None, None, [2], [1, None, None, None, None, None, None, None, None, None, [1]]],
        )
        if isinstance(result, list) and len(result) >= 3 and isinstance(result[2], str):
            return {"id": result[2], "title": title or "Untitled notebook", "source_count": 0}
        raise NotebookLMProtocolError(
            "parse_error",
            "Could not parse created NotebookLM notebook id.",
        )

    def list_sources(self, notebook_id: str) -> list[dict[str, Any]]:
        return parse_sources_from_notebook_data(self.get_notebook(notebook_id))

    def get_conversation_id(self, notebook_id: str) -> str | None:
        try:
            result = self._call_rpc(
                RPC_GET_CONVERSATIONS,
                [[], None, notebook_id, 20],
                source_path=f"/notebook/{notebook_id}",
            )
        except NotebookLMRequestError:
            return None
        value = result
        while isinstance(value, list) and value:
            value = value[0]
        return value if isinstance(value, str) else None

    def ask(
        self,
        *,
        notebook_id: str,
        question: str,
        conversation_id: str | None = None,
    ) -> dict[str, Any]:
        notebook_data = self.get_notebook(notebook_id)
        source_ids = extract_source_ids(notebook_data)
        is_new_conversation = conversation_id is None
        conversation_id = conversation_id or self.get_conversation_id(notebook_id) or str(uuid4())
        conversation_history = self._build_conversation_history(conversation_id)

        body = build_query_body(
            source_ids=source_ids,
            query_text=question,
            conversation_id=conversation_id,
            conversation_history=conversation_history,
            csrf_token=self.auth.csrf_token,
        )
        url = build_query_url(
            self.auth.base_url,
            build_label=self.auth.build_label,
            session_id=self.auth.session_id,
            request_id=self._request_ids.next(),
        )
        response_text = self._post_form(url, body, timeout=self.timeout)
        answer, citations, server_conversation_id = parse_query_response(response_text)
        if server_conversation_id and server_conversation_id != conversation_id:
            if conversation_id in self._conversation_cache:
                self._conversation_cache[server_conversation_id] = self._conversation_cache.pop(
                    conversation_id
                )
            conversation_id = server_conversation_id
        self._cache_conversation_turn(conversation_id, question, answer)
        return {
            "answer": answer,
            "conversation_id": conversation_id,
            "sources_used": citations.get("sources_used", []),
            "citations": citations.get("citations", {}),
            "references": citations.get("references", []),
            "is_follow_up": not is_new_conversation,
        }

    def upload_file(
        self,
        *,
        notebook_id: str,
        file_path: str,
        title: str | None = None,
        wait: bool = True,
    ) -> dict[str, Any]:
        path = Path(file_path)
        if not path.is_file():
            raise NotebookLMRequestError("upload_failed", f"Source file not found: {path}")
        if path.stat().st_size <= 0:
            raise NotebookLMRequestError("upload_failed", f"Source file is empty: {path.name}")

        filename = title or path.name
        source_id = self._register_file_source(notebook_id, filename)
        upload_url = self._start_resumable_upload(
            notebook_id=notebook_id,
            filename=filename,
            file_size=path.stat().st_size,
            source_id=source_id,
        )
        self._upload_file_stream(upload_url, path)
        result = {"id": source_id, "title": filename}
        if wait:
            ready = self._wait_for_source_ready(notebook_id, source_id)
            if ready:
                result.update(ready)
        return result

    def _call_rpc(self, rpc_id: str, params: object, *, source_path: str = "/") -> Any:
        body = build_batchexecute_body(rpc_id, params, self.auth.csrf_token)
        url = build_batchexecute_url(
            self.auth.base_url,
            rpc_id,
            source_path=source_path,
            build_label=self.auth.build_label,
            session_id=self.auth.session_id,
        )
        response_text = self._post_form(url, body, timeout=self.timeout)
        return parse_batchexecute_response(response_text, rpc_id)

    def _build_conversation_history(
        self, conversation_id: str
    ) -> list[list[str | None | int]] | None:
        turns = self._conversation_cache.get(conversation_id, [])
        if not turns:
            return None
        history: list[list[str | None | int]] = []
        for query, answer in turns:
            history.append([answer, None, 2])
            history.append([query, None, 1])
        return history

    def _cache_conversation_turn(self, conversation_id: str, query: str, answer: str) -> None:
        self._conversation_cache.setdefault(conversation_id, []).append((query, answer))

    def _post_form(self, url: str, body: str, *, timeout: float) -> str:
        self.auth.require_cookies()
        headers = {
            "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
            "Origin": self.auth.base_url,
            "Referer": f"{self.auth.base_url}/",
            "X-Same-Domain": "1",
        }
        if self.auth.csrf_token:
            headers["X-Goog-Csrf-Token"] = self.auth.csrf_token
        try:
            with httpx.Client(
                cookies=to_httpx_cookies(self.auth.cookies),
                headers=headers,
                timeout=timeout,
                transport=self._transport,
            ) as client:
                response = client.post(url, content=body)
                response.raise_for_status()
                return response.text
        except httpx.TimeoutException as e:
            raise NotebookLMRequestError("timeout", "NotebookLM request timed out.") from e
        except httpx.HTTPStatusError as e:
            raise NotebookLMRequestError(
                "auth_expired" if e.response.status_code in (400, 401, 403) else "notebooklm_changed",
                f"NotebookLM request failed: HTTP {e.response.status_code}.",
                status_code=e.response.status_code,
            ) from e
        except httpx.HTTPError as e:
            raise NotebookLMRequestError(
                "notebooklm_changed",
                "NotebookLM request failed.",
                debug=e.__class__.__name__,
            ) from e

    def _register_file_source(self, notebook_id: str, filename: str) -> str:
        result = self._call_rpc(
            RPC_ADD_SOURCE_FILE,
            [[[filename]], notebook_id, [2], [1, None, None, None, None, None, None, None, None, None, [1]]],
            source_path=f"/notebook/{notebook_id}",
        )
        source_id = _unwrap_first(result)
        if isinstance(source_id, str):
            return source_id
        raise NotebookLMProtocolError("parse_error", "Could not parse registered source id.")

    def _start_resumable_upload(
        self,
        *,
        notebook_id: str,
        filename: str,
        file_size: int,
        source_id: str,
    ) -> str:
        body = (
            '{"PROJECT_ID":'
            f'{_json_string(notebook_id)},"SOURCE_NAME":{_json_string(filename)},'
            f'"SOURCE_ID":{_json_string(source_id)}}}'
        )
        headers = {
            "Accept": "*/*",
            "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
            "Origin": self.auth.base_url,
            "Referer": f"{self.auth.base_url}/",
            "x-goog-authuser": "0",
            "x-goog-upload-command": "start",
            "x-goog-upload-header-content-length": str(file_size),
            "x-goog-upload-protocol": "resumable",
        }
        try:
            with httpx.Client(
                cookies=to_httpx_cookies(self.auth.cookies),
                timeout=60.0,
                transport=self._transport,
            ) as client:
                response = client.post(f"{self.auth.base_url}/upload/_/?authuser=0", headers=headers, content=body)
                response.raise_for_status()
        except httpx.HTTPError as e:
            raise NotebookLMRequestError("upload_failed", "Could not start NotebookLM upload.") from e
        upload_url = response.headers.get("x-goog-upload-url")
        if not upload_url:
            raise NotebookLMProtocolError("parse_error", "NotebookLM upload URL was missing.")
        return upload_url

    def _upload_file_stream(self, upload_url: str, path: Path) -> None:
        headers = {
            "Accept": "*/*",
            "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
            "Origin": self.auth.base_url,
            "Referer": f"{self.auth.base_url}/",
            "x-goog-authuser": "0",
            "x-goog-upload-command": "upload, finalize",
            "x-goog-upload-offset": "0",
        }

        def chunks() -> Any:
            with path.open("rb") as handle:
                while data := handle.read(65536):
                    yield data

        try:
            with httpx.Client(
                cookies=to_httpx_cookies(self.auth.cookies),
                timeout=300.0,
                transport=self._transport,
            ) as client:
                response = client.post(upload_url, headers=headers, content=chunks())
                response.raise_for_status()
        except httpx.HTTPError as e:
            raise NotebookLMRequestError("upload_failed", "Could not upload file to NotebookLM.") from e

    def _wait_for_source_ready(self, notebook_id: str, source_id: str) -> dict[str, Any] | None:
        deadline = time.time() + self.upload_wait_seconds
        first_unknown_error_at: float | None = None
        while time.time() < deadline:
            now = time.time()
            for source in self.list_sources(notebook_id):
                if source.get("id") == source_id:
                    status = source.get("status")
                    source_type = source.get("source_type")
                    if status in (None, "ready"):
                        return source
                    if status == "error" and isinstance(source_type, int) and source_type != 0:
                        raise NotebookLMRequestError(
                            "upload_failed",
                            "NotebookLM source processing failed.",
                        )
                    if status == "error" and source_type == 0:
                        if first_unknown_error_at is None:
                            first_unknown_error_at = now
                        if now - first_unknown_error_at >= UNKNOWN_SOURCE_ERROR_GRACE_SECONDS:
                            raise NotebookLMRequestError(
                                "upload_failed",
                                "NotebookLM rejected or could not process this source. "
                                "Try a different file or convert it to PDF/TXT before uploading.",
                            )
                    else:
                        first_unknown_error_at = None
            time.sleep(3)
        raise NotebookLMRequestError("timeout", "NotebookLM source processing timed out.")


def _unwrap_first(value: Any) -> Any:
    while isinstance(value, list) and value:
        value = value[0]
    return value


def _json_string(value: str) -> str:
    import json

    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
