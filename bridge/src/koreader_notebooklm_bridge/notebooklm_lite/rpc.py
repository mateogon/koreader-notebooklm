"""Request builders and private RPC constants for nlm-lite."""

from __future__ import annotations

import json
from random import randint
from urllib.parse import quote, urlencode

# Private NotebookLM RPC ids. These can change when NotebookLM changes.
RPC_LIST_NOTEBOOKS = "wXbhsf"
RPC_GET_NOTEBOOK = "rLM1Ne"
RPC_CREATE_NOTEBOOK = "CCqFvf"
RPC_GET_CONVERSATIONS = "hPTbtc"
RPC_ADD_SOURCE_FILE = "o4cbdc"
RPC_RENAME_SOURCE = "b7Wfje"

QUERY_ENDPOINT = (
    "/_/LabsTailwindUi/data/google.internal.labs.tailwind.orchestration.v1."
    "LabsTailwindOrchestrationService/GenerateFreeFormStreamed"
)
BL_FALLBACK = "boq_labs-tailwind-frontend_20260108.06_p0"


class RequestIds:
    def __init__(self) -> None:
        self._value = randint(100000, 999999)

    def next(self) -> int:
        self._value += 100000
        return self._value


def build_batchexecute_body(rpc_id: str, params: object, csrf_token: str = "") -> str:
    params_json = json.dumps(params, separators=(",", ":"), ensure_ascii=False)
    f_req = [[[rpc_id, params_json, None, "generic"]]]
    f_req_json = json.dumps(f_req, separators=(",", ":"), ensure_ascii=False)
    parts = [f"f.req={quote(f_req_json, safe='')}"]
    if csrf_token:
        parts.append(f"at={quote(csrf_token, safe='')}")
    return "&".join(parts) + "&"


def build_batchexecute_url(
    base_url: str,
    rpc_id: str,
    *,
    source_path: str = "/",
    build_label: str = "",
    session_id: str = "",
    language: str = "en",
) -> str:
    params = {
        "rpcids": rpc_id,
        "source-path": source_path,
        "bl": build_label or BL_FALLBACK,
        "hl": language,
        "rt": "c",
    }
    if session_id:
        params["f.sid"] = session_id
    return f"{base_url}/_/LabsTailwindUi/data/batchexecute?{urlencode(params)}"


def build_query_body(
    *,
    source_ids: list[str],
    query_text: str,
    conversation_id: str,
    conversation_history: list[list[str | None | int]] | None = None,
    csrf_token: str = "",
) -> str:
    sources_array = [[[source_id]] for source_id in source_ids]
    params = [sources_array, query_text, conversation_history, [2, None, [1]], conversation_id]
    params_json = json.dumps(params, separators=(",", ":"), ensure_ascii=False)
    f_req = [None, params_json]
    f_req_json = json.dumps(f_req, separators=(",", ":"), ensure_ascii=False)
    parts = [f"f.req={quote(f_req_json, safe='')}"]
    if csrf_token:
        parts.append(f"at={quote(csrf_token, safe='')}")
    return "&".join(parts) + "&"


def build_query_url(
    base_url: str,
    *,
    build_label: str = "",
    session_id: str = "",
    request_id: int,
    language: str = "en",
) -> str:
    params = {
        "bl": build_label or BL_FALLBACK,
        "hl": language,
        "_reqid": str(request_id),
        "rt": "c",
    }
    if session_id:
        params["f.sid"] = session_id
    return f"{base_url}{QUERY_ENDPOINT}?{urlencode(params)}"
