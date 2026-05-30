"""Parsing helpers for NotebookLM's private response formats."""

from __future__ import annotations

from collections.abc import Iterable
import json
from typing import Any

from .errors import NotebookLMProtocolError, NotebookLMRequestError

GOOGLE_ERROR_NAMES = {
    3: "INVALID_ARGUMENT",
    5: "NOT_FOUND",
    7: "PERMISSION_DENIED",
    8: "RESOURCE_EXHAUSTED",
    13: "INTERNAL",
    14: "UNAVAILABLE",
    16: "UNAUTHENTICATED",
}


def parse_batchexecute_response(response_text: str, rpc_id: str) -> Any:
    for chunk in _json_chunks(response_text):
        if not isinstance(chunk, list):
            continue
        for item in chunk:
            if not isinstance(item, list) or len(item) < 3:
                continue
            if item[0] != "wrb.fr" or item[1] != rpc_id:
                continue
            _raise_if_rpc_error(item)
            result = item[2]
            if isinstance(result, str):
                try:
                    return json.loads(result)
                except json.JSONDecodeError:
                    return result
            return result
    return None


def parse_query_response(response_text: str) -> tuple[str, dict[str, Any], str | None]:
    longest_answer = ""
    longest_thinking = ""
    citation_data: dict[str, Any] = {}
    server_conversation_id: str | None = None
    errors: list[dict[str, Any]] = []

    for chunk in _json_chunks(response_text):
        error = _extract_query_error(chunk)
        if error:
            errors.append(error)
            continue
        text, is_answer, citations, conversation_id = _extract_query_answer(chunk)
        if not text:
            continue
        if is_answer and len(text) > len(longest_answer):
            longest_answer = text
            citation_data = citations or {}
            server_conversation_id = conversation_id or server_conversation_id
        elif not is_answer and len(text) > len(longest_thinking):
            longest_thinking = text

    answer = longest_answer or longest_thinking
    if answer:
        return answer, citation_data, server_conversation_id

    if errors:
        error = errors[0]
        raise NotebookLMRequestError(
            _kind_for_rpc_code(error["code"]),
            f"NotebookLM query failed: {error['name']}",
            debug=error.get("type") or error.get("raw"),
            rpc_code=error["code"],
        )

    raise NotebookLMProtocolError(
        "parse_error",
        "NotebookLM returned no answer text.",
    )


def parse_notebooks(result: Any) -> list[dict[str, Any]]:
    notebooks: list[dict[str, Any]] = []
    notebook_list = result[0] if isinstance(result, list) and result and isinstance(result[0], list) else result
    if not isinstance(notebook_list, list):
        return notebooks

    for item in notebook_list:
        if not isinstance(item, list) or len(item) < 3:
            continue
        notebook_id = item[2]
        if not isinstance(notebook_id, str):
            continue
        sources = parse_sources_from_notebook(item)
        notebooks.append(
            {
                "id": notebook_id,
                "title": item[0] if isinstance(item[0], str) else "Untitled",
                "source_count": len(sources),
                "sources": sources,
            }
        )
    return notebooks


def parse_sources_from_notebook_data(result: Any) -> list[dict[str, Any]]:
    if isinstance(result, list) and result and isinstance(result[0], list):
        return parse_sources_from_notebook(result[0])
    return []


def parse_sources_from_notebook(notebook_data: list[Any]) -> list[dict[str, Any]]:
    sources_data = notebook_data[1] if len(notebook_data) > 1 else []
    if not isinstance(sources_data, list):
        return []
    sources: list[dict[str, Any]] = []
    for source in sources_data:
        if not isinstance(source, list) or len(source) < 2:
            continue
        source_id = _unwrap_first(source[0])
        title = source[1] if isinstance(source[1], str) else "Untitled"
        if isinstance(source_id, str):
            parsed: dict[str, Any] = {"id": source_id, "title": title}
            status_code = _source_status_code(source)
            if status_code is not None:
                parsed["status_code"] = status_code
                parsed["status"] = _source_status_name(status_code)
            source_type = _source_type(source)
            if source_type is not None:
                parsed["source_type"] = source_type
            sources.append(parsed)
    return sources


def extract_source_ids(notebook_data: Any) -> list[str]:
    return [source["id"] for source in parse_sources_from_notebook_data(notebook_data)]


def _json_chunks(response_text: str) -> Iterable[Any]:
    if response_text.startswith(")]}'"):
        response_text = response_text[4:]
    lines = response_text.strip().splitlines()
    index = 0
    while index < len(lines):
        line = lines[index].strip()
        if not line:
            index += 1
            continue
        try:
            int(line)
            index += 1
            if index < len(lines):
                yield _loads_or_none(lines[index])
            index += 1
        except ValueError:
            yield _loads_or_none(line)
            index += 1


def _loads_or_none(value: str) -> Any:
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return None


def _raise_if_rpc_error(item: list[Any]) -> None:
    if len(item) <= 5 or not isinstance(item[5], list) or not item[5]:
        return
    error_code = item[5][0]
    if not isinstance(error_code, int):
        return
    detail_type = ""
    if len(item[5]) > 2 and isinstance(item[5][2], list):
        for detail in item[5][2]:
            if isinstance(detail, list) and detail and isinstance(detail[0], str):
                detail_type = detail[0]
                break
    error_name = GOOGLE_ERROR_NAMES.get(error_code, "UNKNOWN")
    raise NotebookLMRequestError(
        _kind_for_rpc_code(error_code),
        f"NotebookLM RPC failed: {error_name}",
        debug=detail_type or None,
        rpc_code=error_code,
    )


def _extract_query_error(chunk: Any) -> dict[str, Any] | None:
    if not isinstance(chunk, list):
        return None
    for item in chunk:
        if not isinstance(item, list) or len(item) < 6:
            continue
        if item[0] != "wrb.fr" or item[2] is not None:
            continue
        error_info = item[5]
        if not isinstance(error_info, list) or not isinstance(error_info[0], int):
            continue
        detail_type = ""
        if len(error_info) > 2 and isinstance(error_info[2], list):
            for detail in error_info[2]:
                if isinstance(detail, list) and detail and isinstance(detail[0], str):
                    detail_type = detail[0]
                    break
        code = error_info[0]
        return {
            "code": code,
            "name": GOOGLE_ERROR_NAMES.get(code, "UNKNOWN"),
            "type": detail_type,
            "raw": str(item)[:500],
        }
    return None


def _extract_query_answer(chunk: Any) -> tuple[str | None, bool, dict[str, Any], str | None]:
    if not isinstance(chunk, list):
        return None, False, {}, None
    for item in chunk:
        if not isinstance(item, list) or len(item) < 3 or item[0] != "wrb.fr":
            continue
        inner_json = item[2]
        if not isinstance(inner_json, str):
            continue
        inner = _loads_or_none(inner_json)
        if not isinstance(inner, list) or not inner:
            continue
        first = inner[0]
        if isinstance(first, str) and len(first) > 0:
            return first, False, {}, None
        if not isinstance(first, list) or not first:
            continue
        answer = first[0]
        if not isinstance(answer, str) or not answer.strip():
            continue
        conversation_id = None
        if len(first) > 2 and isinstance(first[2], list) and first[2]:
            if isinstance(first[2][0], str):
                conversation_id = first[2][0]
        is_answer = False
        citations: dict[str, Any] = {}
        if len(first) > 4 and isinstance(first[4], list):
            type_info = first[4]
            if type_info and isinstance(type_info[-1], int):
                is_answer = type_info[-1] == 1
            if is_answer:
                citations = _extract_citation_data(type_info)
        return answer, is_answer, citations, conversation_id
    return None, False, {}, None


def _extract_citation_data(type_info: list[Any]) -> dict[str, Any]:
    if len(type_info) < 4 or not isinstance(type_info[3], list):
        return {}
    citations: dict[str, str] = {}
    sources: dict[str, None] = {}
    references: list[dict[str, Any]] = []
    for index, passage in enumerate(type_info[3], start=1):
        if not isinstance(passage, list) or len(passage) < 2:
            continue
        detail = passage[1]
        if not isinstance(detail, list) or len(detail) < 6:
            continue
        source_id = _nested_get(detail, [5, 0, 0, 0])
        if not isinstance(source_id, str):
            continue
        citations[str(index)] = source_id
        sources[source_id] = None
        ref: dict[str, Any] = {"source_id": source_id, "citation_number": index}
        cited_text = _extract_cited_text(detail)
        if cited_text:
            ref["cited_text"] = cited_text
        references.append(ref)
    if not citations:
        return {}
    return {
        "sources_used": list(sources.keys()),
        "citations": citations,
        "references": references,
    }


def _extract_cited_text(detail: list[Any]) -> str | None:
    if len(detail) <= 4 or not isinstance(detail[4], list):
        return None
    texts: list[str] = []
    for element in detail[4]:
        segments = [element] if isinstance(element, list) and element and isinstance(element[0], (int, float)) else element
        if not isinstance(segments, list):
            continue
        for segment in segments:
            if not isinstance(segment, list) or len(segment) < 3 or not isinstance(segment[0], (int, float)):
                continue
            nested = segment[2]
            if not isinstance(nested, list):
                continue
            for group in nested:
                if not isinstance(group, list):
                    continue
                for item in group:
                    if isinstance(item, list) and len(item) >= 3:
                        value = item[2]
                        if isinstance(value, str) and value.strip():
                            texts.append(value.strip())
                        elif isinstance(value, list):
                            texts.extend(part.strip() for part in value if isinstance(part, str) and part.strip())
    return " ".join(texts) if texts else None


def _unwrap_first(value: Any) -> Any:
    while isinstance(value, list) and value:
        value = value[0]
    return value


def _source_status_code(source: list[Any]) -> int | None:
    if len(source) <= 3 or not isinstance(source[3], list) or len(source[3]) <= 1:
        return None
    return source[3][1] if isinstance(source[3][1], int) else None


def _source_type(source: list[Any]) -> int | None:
    if len(source) <= 2 or not isinstance(source[2], list) or len(source[2]) <= 4:
        return None
    return source[2][4] if isinstance(source[2][4], int) else None


def _source_status_name(status_code: int) -> str:
    return {
        1: "processing",
        2: "ready",
        3: "error",
        5: "preparing",
    }.get(status_code, "unknown")


def _nested_get(value: Any, path: list[int]) -> Any:
    for key in path:
        if not isinstance(value, list) or len(value) <= key:
            return None
        value = value[key]
    return value


def _kind_for_rpc_code(code: int) -> str:
    if code == 5:
        return "not_found"
    if code == 7:
        return "permission_denied"
    if code == 8:
        return "rate_limited"
    if code == 16:
        return "auth_expired"
    return "notebooklm_changed"
