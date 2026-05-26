"""NLM subprocess adapter tests."""

from types import SimpleNamespace

import pytest

from koreader_notebooklm_bridge.adapters.errors import (
    AdapterCommandError,
    AdapterNotConfiguredError,
)
from koreader_notebooklm_bridge.adapters.notebooklm import NlmNotebookLMAdapter
from koreader_notebooklm_bridge.config import BridgeConfig
from koreader_notebooklm_bridge.models import AskRequest, SourceUploadRequest


def test_nlm_list_notebooks_parses_json(monkeypatch):
    calls = []

    def fake_run(command, **kwargs):
        calls.append((command, kwargs))
        return SimpleNamespace(
            returncode=0,
            stdout='[{"id":"nb1","title":"Notebook One","source_count":2}]',
            stderr="",
        )

    monkeypatch.setattr("koreader_notebooklm_bridge.adapters.notebooklm.subprocess.run", fake_run)
    adapter = NlmNotebookLMAdapter(BridgeConfig(adapter="nlm", nlm_profile="work"))

    notebooks = adapter.list_notebooks()

    assert notebooks[0].id == "nb1"
    assert notebooks[0].source_count == 2
    assert calls[0][0] == ["nlm", "notebook", "list", "--json", "--profile", "work"]


def test_nlm_ask_uses_default_notebook_and_parses_response(monkeypatch):
    calls = []

    def fake_run(command, **kwargs):
        calls.append(command)
        return SimpleNamespace(
            returncode=0,
            stdout='{"answer":"Answer text","conversation_id":"conv1","sources_used":["src1"],"citations":{"1":"src1"},"references":[{"source_id":"src1"}]}',
            stderr="",
        )

    monkeypatch.setattr("koreader_notebooklm_bridge.adapters.notebooklm.subprocess.run", fake_run)
    adapter = NlmNotebookLMAdapter(
        BridgeConfig(adapter="nlm", default_notebook_id="default-nb", nlm_timeout_seconds=9)
    )

    response = adapter.ask(
        AskRequest(selected_text="Important passage.", prompt="Explain this simply.")
    )

    assert response.answer == "Answer text"
    assert response.notebook_id == "default-nb"
    assert response.conversation_id == "conv1"
    assert response.sources_used == ["src1"]
    assert calls[0][0:5] == ["nlm", "notebook", "query", "--json", "--timeout"]
    assert calls[0][5] == "9"
    assert calls[0][6] == "default-nb"
    assert "Important passage." in calls[0][7]


def test_nlm_ask_accepts_cli_value_wrapper(monkeypatch):
    def fake_run(command, **kwargs):
        return SimpleNamespace(
            returncode=0,
            stdout='{"value":{"answer":"Wrapped answer","conversation_id":"conv1","sources_used":[],"citations":{},"references":[]}}',
            stderr="",
        )

    monkeypatch.setattr("koreader_notebooklm_bridge.adapters.notebooklm.subprocess.run", fake_run)
    adapter = NlmNotebookLMAdapter(BridgeConfig(adapter="nlm", default_notebook_id="default-nb"))

    response = adapter.ask(AskRequest(selected_text="Text.", prompt="Explain."))

    assert response.answer == "Wrapped answer"


def test_nlm_ask_requires_notebook_id():
    adapter = NlmNotebookLMAdapter(BridgeConfig(adapter="nlm"))

    with pytest.raises(AdapterNotConfiguredError):
        adapter.ask(AskRequest(selected_text="Text.", prompt="Explain."))


def test_nlm_command_failure_raises_adapter_error(monkeypatch):
    def fake_run(command, **kwargs):
        return SimpleNamespace(returncode=1, stdout="", stderr="auth failed")

    monkeypatch.setattr("koreader_notebooklm_bridge.adapters.notebooklm.subprocess.run", fake_run)
    adapter = NlmNotebookLMAdapter(BridgeConfig(adapter="nlm"))

    with pytest.raises(AdapterCommandError, match="auth failed"):
        adapter.list_notebooks()


def test_nlm_create_notebook_extracts_id(monkeypatch):
    def fake_run(command, **kwargs):
        return SimpleNamespace(returncode=0, stdout="Created notebook\n  ID: abc-123\n", stderr="")

    monkeypatch.setattr("koreader_notebooklm_bridge.adapters.notebooklm.subprocess.run", fake_run)
    adapter = NlmNotebookLMAdapter(BridgeConfig(adapter="nlm"))

    response = adapter.create_notebook("Bridge Test")

    assert response.notebook.id == "abc-123"
    assert response.url == "https://notebooklm.google.com/notebook/abc-123"


def test_nlm_upload_source_extracts_id(monkeypatch):
    calls = []

    def fake_run(command, **kwargs):
        calls.append(command)
        if command[1:4] == ["source", "list", "nb1"]:
            return SimpleNamespace(returncode=0, stdout="[]", stderr="")
        return SimpleNamespace(returncode=0, stdout="Added source\n  ID: src-123\n", stderr="")

    monkeypatch.setattr("koreader_notebooklm_bridge.adapters.notebooklm.subprocess.run", fake_run)
    adapter = NlmNotebookLMAdapter(BridgeConfig(adapter="nlm"))

    response = adapter.upload_source(
        SourceUploadRequest(notebook_id="nb1", file_path="/tmp/book.pdf", title="Book PDF")
    )

    assert response.source_id == "src-123"
    assert calls[0] == ["nlm", "source", "list", "nb1", "--json"]
    assert calls[1] == [
        "nlm",
        "source",
        "add",
        "nb1",
        "--file",
        "/tmp/book.pdf",
        "--title",
        "Book PDF",
        "--wait",
    ]


def test_nlm_upload_source_infers_id_from_source_list(monkeypatch):
    calls = []

    def fake_run(command, **kwargs):
        calls.append(command)
        if len(calls) == 1:
            return SimpleNamespace(
                returncode=0,
                stdout='[{"id":"existing","title":"Existing","type":"generated_text","url":null}]',
                stderr="",
            )
        if len(calls) == 2:
            return SimpleNamespace(returncode=0, stdout="Added source without id", stderr="")
        return SimpleNamespace(
            returncode=0,
            stdout='[{"id":"src-new","title":"New Source","type":"generated_text","url":null},{"id":"existing","title":"Existing","type":"generated_text","url":null}]',
            stderr="",
        )

    monkeypatch.setattr("koreader_notebooklm_bridge.adapters.notebooklm.subprocess.run", fake_run)
    adapter = NlmNotebookLMAdapter(BridgeConfig(adapter="nlm"))

    response = adapter.upload_source(
        SourceUploadRequest(notebook_id="nb1", file_path="/tmp/book.pdf")
    )

    assert response.source_id == "src-new"
    assert response.title == "New Source"
    assert len(calls) == 3
