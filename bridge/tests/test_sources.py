"""Source endpoint tests."""

from fastapi.testclient import TestClient

from koreader_notebooklm_bridge.app import app


def test_source_upload_returns_mock_source():
    client = TestClient(app)

    response = client.post(
        "/sources/upload",
        json={
            "notebook_id": "mock-notebook",
            "file_path": "/tmp/example.pdf",
            "title": "Example PDF",
        },
    )

    assert response.status_code == 200
    assert response.json() == {
        "ok": True,
        "source_id": "mock-source",
        "title": "Example PDF",
        "notebook_id": "mock-notebook",
        "adapter": "mock",
    }
