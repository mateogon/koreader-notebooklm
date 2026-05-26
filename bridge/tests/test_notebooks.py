"""Notebook endpoint tests."""

from fastapi.testclient import TestClient

from koreader_notebooklm_bridge.app import app


def test_notebooks_returns_mock_list():
    client = TestClient(app)

    response = client.get("/notebooks")

    assert response.status_code == 200
    assert response.json() == {
        "ok": True,
        "notebooks": [
            {
                "id": "mock-notebook",
                "title": "Mock Notebook",
                "source_count": 1,
            }
        ],
    }


def test_create_notebook_returns_mock_notebook():
    client = TestClient(app)

    response = client.post("/notebooks", json={"title": "New Notebook"})

    assert response.status_code == 200
    assert response.json() == {
        "ok": True,
        "notebook": {
            "id": "mock-created-notebook",
            "title": "New Notebook",
            "source_count": 0,
        },
        "url": None,
        "adapter": "mock",
    }
