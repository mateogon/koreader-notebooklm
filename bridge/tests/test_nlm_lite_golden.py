"""Golden request/response contracts for the nlm-lite Lua port."""

from __future__ import annotations

import json
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

import httpx

from koreader_notebooklm_bridge.notebooklm_lite.auth import AuthBundle
from koreader_notebooklm_bridge.notebooklm_lite.client import NotebookLMLiteClient
from koreader_notebooklm_bridge.notebooklm_lite.parsing import (
    parse_batchexecute_response,
    parse_notebooks,
    parse_query_response,
    parse_sources_from_notebook_data,
)
from koreader_notebooklm_bridge.notebooklm_lite.rpc import (
    QUERY_ENDPOINT,
    RPC_ADD_SOURCE_FILE,
    RPC_CREATE_NOTEBOOK,
    RPC_GET_NOTEBOOK,
    RPC_LIST_NOTEBOOKS,
    build_batchexecute_body,
    build_batchexecute_url,
    build_query_body,
    build_query_url,
)

FIXTURES = Path(__file__).parent / "fixtures" / "nlm_lite"

CREATE_NOTEBOOK_PARAMS = [
    "Golden Notebook",
    None,
    None,
    [2],
    [1, None, None, None, None, None, None, None, None, None, [1]],
]
REGISTER_FILE_PARAMS = [
    [["Golden Source.pdf"]],
    "nb-golden",
    [2],
    [1, None, None, None, None, None, None, None, None, None, [1]],
]


def test_golden_batchexecute_request_shapes():
    rpc_id, params, _, mode = _decode_rpc_call(
        build_batchexecute_body(
            RPC_LIST_NOTEBOOKS,
            [None, 1, None, [2]],
            csrf_token="csrf-token",
        )
    )
    assert rpc_id == RPC_LIST_NOTEBOOKS
    assert params == [None, 1, None, [2]]
    assert mode == "generic"

    get_url = build_batchexecute_url(
        "https://notebooklm.google.com",
        RPC_GET_NOTEBOOK,
        source_path="/notebook/nb-golden",
        build_label="build-label",
        session_id="session-id",
    )
    get_query = parse_qs(urlparse(get_url).query)
    assert get_query["rpcids"] == [RPC_GET_NOTEBOOK]
    assert get_query["source-path"] == ["/notebook/nb-golden"]
    assert get_query["bl"] == ["build-label"]
    assert get_query["f.sid"] == ["session-id"]
    _, get_params, _, _ = _decode_rpc_call(
        build_batchexecute_body(
            RPC_GET_NOTEBOOK,
            ["nb-golden", None, [2], None, 0],
            csrf_token="csrf-token",
        )
    )
    assert get_params == ["nb-golden", None, [2], None, 0]

    rpc_id, create_params, _, _ = _decode_rpc_call(
        build_batchexecute_body(
            RPC_CREATE_NOTEBOOK,
            CREATE_NOTEBOOK_PARAMS,
            csrf_token="csrf-token",
        )
    )
    assert rpc_id == RPC_CREATE_NOTEBOOK
    assert create_params == CREATE_NOTEBOOK_PARAMS

    rpc_id, register_params, _, _ = _decode_rpc_call(
        build_batchexecute_body(
            RPC_ADD_SOURCE_FILE,
            REGISTER_FILE_PARAMS,
            csrf_token="csrf-token",
        )
    )
    assert rpc_id == RPC_ADD_SOURCE_FILE
    assert register_params == REGISTER_FILE_PARAMS


def test_golden_query_request_shape():
    history = [
        ["Earlier answer.", None, 2],
        ["Earlier question?", None, 1],
    ]
    body = build_query_body(
        source_ids=["src-golden"],
        query_text="Why does this matter?",
        conversation_id="conv-golden",
        conversation_history=history,
        csrf_token="csrf-token",
    )

    values = _decode_form_body(body)
    f_req = json.loads(unquote(values["f.req"][0]))
    params = json.loads(f_req[1])
    assert params == [
        [[["src-golden"]]],
        "Why does this matter?",
        history,
        [2, None, [1]],
        "conv-golden",
    ]
    assert values["at"] == ["csrf-token"]

    url = build_query_url(
        "https://notebooklm.google.com",
        build_label="build-label",
        session_id="session-id",
        request_id=123456,
    )
    query = parse_qs(urlparse(url).query)
    assert urlparse(url).path == QUERY_ENDPOINT
    assert query["_reqid"] == ["123456"]
    assert query["bl"] == ["build-label"]
    assert query["f.sid"] == ["session-id"]


def test_golden_upload_start_and_finalize_shapes(tmp_path):
    source = tmp_path / "source.pdf"
    source.write_bytes(b"%PDF-1.4\nGolden source\n")
    calls: list[dict[str, object]] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if "batchexecute" in str(request.url):
            calls.append({"step": "register", "request": request})
            _, params, _, _ = _decode_rpc_call(request.content.decode("utf-8"))
            assert params == REGISTER_FILE_PARAMS
            return httpx.Response(
                200,
                text=_batchexecute_response(RPC_ADD_SOURCE_FILE, [[["src-golden-upload"]]]),
            )
        if str(request.url).endswith("/upload/_/?authuser=0"):
            calls.append(
                {
                    "step": "start",
                    "headers": dict(request.headers),
                    "body": json.loads(request.content.decode("utf-8")),
                }
            )
            return httpx.Response(
                200,
                headers={"x-goog-upload-url": "https://upload.test/golden-session"},
            )
        if str(request.url) == "https://upload.test/golden-session":
            calls.append(
                {
                    "step": "finalize",
                    "headers": dict(request.headers),
                    "body": request.content,
                }
            )
            return httpx.Response(200)
        raise AssertionError(f"unexpected request: {request.url}")

    client = NotebookLMLiteClient(_auth_bundle(), transport=httpx.MockTransport(handler))

    result = client.upload_file(
        notebook_id="nb-golden",
        file_path=str(source),
        title="Golden Source.pdf",
        wait=False,
    )

    assert result == {"id": "src-golden-upload", "title": "Golden Source.pdf"}
    assert [call["step"] for call in calls] == ["register", "start", "finalize"]

    start = calls[1]
    assert start["body"] == {
        "PROJECT_ID": "nb-golden",
        "SOURCE_NAME": "Golden Source.pdf",
        "SOURCE_ID": "src-golden-upload",
    }
    start_headers = start["headers"]
    assert start_headers["x-goog-upload-command"] == "start"
    assert start_headers["x-goog-upload-header-content-length"] == str(source.stat().st_size)
    assert start_headers["x-goog-upload-protocol"] == "resumable"

    finalize = calls[2]
    finalize_headers = finalize["headers"]
    assert finalize_headers["x-goog-upload-command"] == "upload, finalize"
    assert finalize_headers["x-goog-upload-offset"] == "0"
    assert finalize["body"] == b"%PDF-1.4\nGolden source\n"


def test_golden_response_parsing_fixtures():
    list_result = parse_batchexecute_response(
        (FIXTURES / "notebook_list_response.fixture").read_text(encoding="utf-8"),
        RPC_LIST_NOTEBOOKS,
    )
    assert parse_notebooks(list_result) == [
        {
            "id": "nb-golden",
            "title": "Golden Notebook",
            "source_count": 1,
            "sources": [
                {
                    "id": "src-golden",
                    "title": "Golden Source",
                    "status_code": 2,
                    "status": "ready",
                }
            ],
        }
    ]

    notebook_result = parse_batchexecute_response(
        (FIXTURES / "get_notebook_response.fixture").read_text(encoding="utf-8"),
        RPC_GET_NOTEBOOK,
    )
    assert parse_sources_from_notebook_data(notebook_result) == [
        {
            "id": "src-golden",
            "title": "Golden Source",
            "status_code": 2,
            "status": "ready",
        }
    ]

    answer, citations, conversation_id = parse_query_response(
        (FIXTURES / "query_response.fixture").read_text(encoding="utf-8")
    )
    assert answer == "Golden answer with citation [1]."
    assert conversation_id == "conv-golden"
    assert citations == {
        "sources_used": ["src-golden"],
        "citations": {"1": "src-golden"},
        "references": [
            {
                "source_id": "src-golden",
                "citation_number": 1,
                "cited_text": "Golden cited passage.",
            }
        ],
    }


def _auth_bundle() -> AuthBundle:
    return AuthBundle(
        cookies={"SID": "secret"},
        csrf_token="csrf-token",
        session_id="session-id",
        build_label="build-label",
    )


def _decode_form_body(body: str) -> dict[str, list[str]]:
    return parse_qs(body, keep_blank_values=True)


def _decode_rpc_call(body: str) -> tuple[str, object, object, str]:
    values = _decode_form_body(body)
    f_req = json.loads(unquote(values["f.req"][0]))
    assert values["at"] == ["csrf-token"]
    call = f_req[0][0]
    return call[0], json.loads(call[1]), call[2], call[3]


def _batchexecute_response(rpc_id: str, result: object) -> str:
    payload = [["wrb.fr", rpc_id, json.dumps(result, separators=(",", ":")), None, None, None]]
    line = json.dumps(payload, separators=(",", ":"))
    return f")]}}'\n{len(line)}\n{line}\n"
