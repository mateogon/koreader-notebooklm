"""NLM Lite direct adapter tests."""

from __future__ import annotations

import json
import os
from urllib.parse import parse_qs, unquote
import subprocess

import httpx
import pytest

from koreader_notebooklm_bridge.adapters.factory import create_adapter
from koreader_notebooklm_bridge.adapters.notebooklm_lite import NlmLiteNotebookLMAdapter
from koreader_notebooklm_bridge.config import BridgeConfig, load_config
from koreader_notebooklm_bridge.models import AskRequest
from koreader_notebooklm_bridge.notebooklm_lite.auth import (
    AuthBundle,
    export_nlm_auth_bundle,
    extract_page_tokens,
    load_auth_bundle,
)
from koreader_notebooklm_bridge.notebooklm_lite.client import NotebookLMLiteClient
from koreader_notebooklm_bridge.notebooklm_lite.parsing import (
    parse_batchexecute_response,
    parse_query_response,
)
from koreader_notebooklm_bridge.notebooklm_lite.rpc import (
    RPC_ADD_SOURCE_FILE,
    RPC_CREATE_NOTEBOOK,
    RPC_GET_CONVERSATIONS,
    RPC_GET_NOTEBOOK,
    RPC_LIST_NOTEBOOKS,
)


def test_load_config_reads_nlm_lite_env(monkeypatch, tmp_path):
    bundle = tmp_path / "auth.json"
    monkeypatch.setenv("KOREADER_NOTEBOOKLM_ADAPTER", "nlm-lite")
    monkeypatch.setenv("KOREADER_NOTEBOOKLM_AUTH_BUNDLE", str(bundle))
    monkeypatch.setenv("KOREADER_NOTEBOOKLM_BASE_URL", "https://notebooklm.google.com/")
    monkeypatch.setenv("KOREADER_NOTEBOOKLM_DIRECT_TIMEOUT_SECONDS", "33")
    monkeypatch.setenv("KOREADER_NOTEBOOKLM_UPLOAD_WAIT_SECONDS", "44")

    config = load_config()

    assert config.adapter == "nlm-lite"
    assert config.auth_bundle_path == bundle
    assert config.notebooklm_base_url == "https://notebooklm.google.com"
    assert config.direct_timeout_seconds == 33
    assert config.upload_wait_seconds == 44


def test_factory_creates_nlm_lite_adapter():
    adapter = create_adapter(BridgeConfig(adapter="nlm-lite"))

    assert isinstance(adapter, NlmLiteNotebookLMAdapter)
    assert adapter.name == "nlm-lite"


def test_auth_bundle_loads_explicit_file(tmp_path):
    bundle_path = tmp_path / "auth.json"
    bundle_path.write_text(
        json.dumps(
            {
                "base_url": "https://notebooklm.google.com",
                "cookies": {"SID": "secret"},
                "csrf_token": "csrf",
                "session_id": "sid",
                "build_label": "build",
                "extracted_at": 12,
            }
        ),
        encoding="utf-8",
    )

    bundle = load_auth_bundle(bundle_path=bundle_path)

    assert bundle.csrf_token == "csrf"
    assert bundle.session_id == "sid"
    assert bundle.build_label == "build"
    assert bundle.cookies == {"SID": "secret"}


def test_export_nlm_auth_bundle_writes_portable_bundle(tmp_path):
    storage = tmp_path / "nlm"
    profile_dir = storage / "profiles" / "fresh"
    profile_dir.mkdir(parents=True)
    (profile_dir / "cookies.json").write_text(
        json.dumps([{"name": "SID", "value": "secret", "domain": ".google.com"}]),
        encoding="utf-8",
    )
    (profile_dir / "metadata.json").write_text(
        json.dumps(
            {
                "csrf_token": "csrf",
                "session_id": "sid",
                "build_label": "build",
            }
        ),
        encoding="utf-8",
    )
    output = tmp_path / "out" / "fresh-auth-bundle.json"

    written = export_nlm_auth_bundle(
        profile="fresh",
        output_path=output,
        storage_dir=storage,
    )

    assert written == output
    bundle = json.loads(output.read_text(encoding="utf-8"))
    assert bundle["schema"] == "koreader-notebooklm-auth-bundle/v1"
    assert bundle["provider"] == "nlm-profile-export"
    assert bundle["profile"] == "fresh"
    assert bundle["cookies"][0]["name"] == "SID"
    assert bundle["csrf_token"] == "csrf"
    assert bundle["session_id"] == "sid"
    assert bundle["build_label"] == "build"
    assert output.stat().st_mode & 0o777 == 0o600

    loaded = load_auth_bundle(bundle_path=output)
    assert loaded.csrf_token == "csrf"
    assert loaded.cookies == bundle["cookies"]


def test_extract_page_tokens_from_html():
    tokens = extract_page_tokens(
        'before "SNlM0e":"csrf-token" middle "FdrFJe":"session-id" "cfb2h":"build-label"'
    )

    assert tokens.csrf_token == "csrf-token"
    assert tokens.session_id == "session-id"
    assert tokens.build_label == "build-label"


def test_parse_batchexecute_notebook_list():
    result = [[["Notebook One", [[["src1"], "Source One"]], "nb1"]]]
    response = _batchexecute_response(RPC_LIST_NOTEBOOKS, result)

    parsed = parse_batchexecute_response(response, RPC_LIST_NOTEBOOKS)

    assert parsed == result


def test_parse_query_response_with_citations():
    response = _query_response(
        answer="This is a direct NotebookLM answer with citation [1].",
        conversation_id="conv1",
        source_id="src1",
        cited_text="Cited passage.",
    )

    answer, citations, conversation_id = parse_query_response(response)

    assert answer.startswith("This is a direct")
    assert conversation_id == "conv1"
    assert citations["sources_used"] == ["src1"]
    assert citations["citations"] == {"1": "src1"}
    assert citations["references"][0]["cited_text"] == "Cited passage."


def test_client_lists_notebooks_without_subprocess(monkeypatch):
    def fail_subprocess(*args, **kwargs):
        raise AssertionError("nlm-lite must not call subprocess.run")

    monkeypatch.setattr(subprocess, "run", fail_subprocess)

    def handler(request: httpx.Request) -> httpx.Response:
        assert "batchexecute" in str(request.url)
        assert request.url.params["rpcids"] == RPC_LIST_NOTEBOOKS
        result = [[["Notebook One", [[["src1"], "Source One"]], "nb1"]]]
        return httpx.Response(200, text=_batchexecute_response(RPC_LIST_NOTEBOOKS, result))

    client = NotebookLMLiteClient(_auth_bundle(), transport=httpx.MockTransport(handler))

    notebooks = client.list_notebooks()

    assert notebooks == [
        {
            "id": "nb1",
            "title": "Notebook One",
            "source_count": 1,
            "sources": [{"id": "src1", "title": "Source One"}],
        }
    ]


def test_client_ask_uses_direct_http():
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "batchexecute" in url and request.url.params["rpcids"] == RPC_GET_NOTEBOOK:
            result = [["Notebook One", [[["src1"], "Source One"]], "nb1"]]
            return httpx.Response(200, text=_batchexecute_response(RPC_GET_NOTEBOOK, result))
        if "batchexecute" in url and request.url.params["rpcids"] == RPC_GET_CONVERSATIONS:
            return httpx.Response(
                200,
                text=_batchexecute_response(RPC_GET_CONVERSATIONS, [[["conv-existing"]]]),
            )
        if "GenerateFreeFormStreamed" in url:
            body = request.content.decode("utf-8")
            assert "Explain%20this" in body
            return httpx.Response(
                200,
                text=_query_response(
                    answer="This is an answer from the direct client.",
                    conversation_id="conv-existing",
                    source_id="src1",
                    cited_text="A useful source passage.",
                ),
            )
        raise AssertionError(f"unexpected request: {request.url}")

    client = NotebookLMLiteClient(_auth_bundle(), transport=httpx.MockTransport(handler))

    response = client.ask(notebook_id="nb1", question="Explain this.")

    assert response["answer"] == "This is an answer from the direct client."
    assert response["conversation_id"] == "conv-existing"
    assert response["sources_used"] == ["src1"]


def test_client_ask_sends_cached_history_for_follow_up():
    query_bodies = []

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if "batchexecute" in url and request.url.params["rpcids"] == RPC_GET_NOTEBOOK:
            result = [["Notebook One", [[["src1"], "Source One"]], "nb1"]]
            return httpx.Response(200, text=_batchexecute_response(RPC_GET_NOTEBOOK, result))
        if "GenerateFreeFormStreamed" in url:
            body = request.content.decode("utf-8")
            query_bodies.append(body)
            answer = "First direct answer." if len(query_bodies) == 1 else "Follow-up answer."
            return httpx.Response(
                200,
                text=_query_response(
                    answer=answer,
                    conversation_id="conv1",
                    source_id="src1",
                    cited_text="A useful source passage.",
                ),
            )
        raise AssertionError(f"unexpected request: {request.url}")

    client = NotebookLMLiteClient(_auth_bundle(), transport=httpx.MockTransport(handler))

    client.ask(notebook_id="nb1", question="First question.", conversation_id="conv1")
    client.ask(notebook_id="nb1", question="Follow-up question.", conversation_id="conv1")

    assert len(query_bodies) == 2
    decoded_second = _decode_f_req(query_bodies[1])
    params = json.loads(decoded_second[1])
    assert params[2] == [
        ["First direct answer.", None, 2],
        ["First question.", None, 1],
    ]


def test_client_create_notebook_parses_id():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["rpcids"] == RPC_CREATE_NOTEBOOK
        return httpx.Response(
            200,
            text=_batchexecute_response(
                RPC_CREATE_NOTEBOOK,
                ["Created Notebook", None, "created-nb"],
            ),
        )

    client = NotebookLMLiteClient(_auth_bundle(), transport=httpx.MockTransport(handler))

    response = client.create_notebook("Created Notebook")

    assert response == {
        "id": "created-nb",
        "title": "Created Notebook",
        "source_count": 0,
    }


def test_client_upload_file_uses_resumable_flow(tmp_path):
    source = tmp_path / "source.md"
    source.write_text("# Source\n\nText.", encoding="utf-8")
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(str(request.url))
        if "batchexecute" in str(request.url):
            assert request.url.params["rpcids"] == RPC_ADD_SOURCE_FILE
            decoded = _decode_f_req(request.content.decode("utf-8"))
            params = json.loads(decoded[0][0][1])
            assert params[0] == [["Readable Source"]]
            assert params[1] == "nb1"
            return httpx.Response(
                200,
                text=_batchexecute_response(RPC_ADD_SOURCE_FILE, [[["src-new"]]]),
            )
        if str(request.url).endswith("/upload/_/?authuser=0"):
            assert request.headers["x-goog-upload-command"] == "start"
            return httpx.Response(200, headers={"x-goog-upload-url": "https://upload.test/session"})
        if str(request.url) == "https://upload.test/session":
            assert request.headers["x-goog-upload-command"] == "upload, finalize"
            assert request.content == b"# Source\n\nText."
            return httpx.Response(200)
        raise AssertionError(f"unexpected request: {request.url}")

    client = NotebookLMLiteClient(_auth_bundle(), transport=httpx.MockTransport(handler))

    response = client.upload_file(
        notebook_id="nb1",
        file_path=str(source),
        title="Readable Source",
        wait=False,
    )

    assert response == {"id": "src-new", "title": "Readable Source"}
    assert len(calls) == 3


def test_adapter_ask_maps_client_response(monkeypatch):
    class FakeClient:
        def ask(self, **kwargs):
            assert kwargs["conversation_id"] == "conv1"
            return {
                "answer": "Adapter answer",
                "conversation_id": "conv1",
                "sources_used": ["src1"],
                "citations": {"1": "src1"},
                "references": [{"source_id": "src1"}],
            }

    adapter = NlmLiteNotebookLMAdapter(
        BridgeConfig(adapter="nlm-lite", default_notebook_id="nb1")
    )
    monkeypatch.setattr(adapter, "_get_client", lambda: FakeClient())

    response = adapter.ask(
        AskRequest(selected_text="Selected text.", prompt="Prompt.", conversation_id="conv1")
    )

    assert response.adapter == "nlm-lite"
    assert response.answer == "Adapter answer"
    assert response.notebook_id == "nb1"
    assert response.conversation_id == "conv1"


@pytest.mark.skipif(
    os.getenv("KOREADER_NOTEBOOKLM_RUN_LIVE_NLM_LITE_TESTS") != "1",
    reason="Live NotebookLM tests are opt-in.",
)
def test_live_nlm_lite_lists_notebooks():
    adapter = NlmLiteNotebookLMAdapter(BridgeConfig(adapter="nlm-lite"))

    notebooks = adapter.list_notebooks()

    assert notebooks
    assert notebooks[0].id


@pytest.mark.skipif(
    os.getenv("KOREADER_NOTEBOOKLM_RUN_LIVE_NLM_LITE_TESTS") != "1",
    reason="Live NotebookLM tests are opt-in.",
)
def test_live_nlm_lite_asks_default_notebook():
    notebook_id = os.getenv("KOREADER_NOTEBOOKLM_DEFAULT_NOTEBOOK_ID")
    if not notebook_id:
        pytest.skip("KOREADER_NOTEBOOKLM_DEFAULT_NOTEBOOK_ID is required for live ask.")
    adapter = NlmLiteNotebookLMAdapter(
        BridgeConfig(adapter="nlm-lite", default_notebook_id=notebook_id)
    )

    response = adapter.ask(
        AskRequest(
            selected_text="KOReader NotebookLM live smoke.",
            prompt="Respond with one short sentence about this phrase.",
        )
    )

    assert response.answer.strip()
    assert response.adapter == "nlm-lite"


def _auth_bundle() -> AuthBundle:
    return AuthBundle(
        cookies={"SID": "secret"},
        csrf_token="csrf",
        session_id="session",
        build_label="build",
    )


def _batchexecute_response(rpc_id: str, result: object) -> str:
    payload = [["wrb.fr", rpc_id, json.dumps(result, separators=(",", ":")), None, None, None]]
    line = json.dumps(payload, separators=(",", ":"))
    return f")]}}'\n{len(line)}\n{line}\n"


def _query_response(
    *,
    answer: str,
    conversation_id: str,
    source_id: str,
    cited_text: str,
) -> str:
    detail = [
        None,
        None,
        None,
        None,
        [[0, 1, [[[0, 1, cited_text]]]]],
        [[[source_id]]],
    ]
    inner = [[answer, None, [conversation_id], None, [None, None, None, [["p1", detail]], 1]]]
    payload = [["wrb.fr", None, json.dumps(inner, separators=(",", ":")), None, None, None]]
    line = json.dumps(payload, separators=(",", ":"))
    return f")]}}'\n{len(line)}\n{line}\n"


def _decode_f_req(body: str) -> list:
    values = parse_qs(body, keep_blank_values=True)
    return json.loads(unquote(values["f.req"][0]))
