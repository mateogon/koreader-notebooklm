"""Ask endpoint tests."""

from fastapi.testclient import TestClient

from koreader_notebooklm_bridge.app import app


def test_ask_returns_mock_response():
    client = TestClient(app)

    response = client.post(
        "/ask",
        json={
            "notebook_id": "mock-notebook",
            "selected_text": "This is the selected passage.",
            "prompt": "Explain this simply.",
            "book": {"title": "Example Book"},
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["notebook_id"] == "mock-notebook"
    assert body["adapter"] == "mock"
    assert "Explain this simply." in body["answer"]
    assert "This is the selected passage." in body["answer"]


def test_ask_rejects_empty_selection():
    client = TestClient(app)

    response = client.post(
        "/ask",
        json={
            "selected_text": "",
            "prompt": "Explain this simply.",
        },
    )

    assert response.status_code == 422
