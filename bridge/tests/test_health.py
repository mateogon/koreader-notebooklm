"""Health endpoint tests."""

from fastapi.testclient import TestClient

from koreader_notebooklm_bridge.app import app


def test_health_returns_ok():
    client = TestClient(app)

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "ok": True,
        "service": "koreader-notebooklm-bridge",
        "adapter": "mock",
        "default_notebook_id": None,
    }
