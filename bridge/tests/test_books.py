"""Book mapping endpoint tests."""

from fastapi.testclient import TestClient

from koreader_notebooklm_bridge.app import create_app
from koreader_notebooklm_bridge.config import BridgeConfig


def test_book_link_round_trip(tmp_path):
    app = create_app(BridgeConfig(adapter="mock", data_dir=tmp_path))
    client = TestClient(app)

    link_response = client.post(
        "/books/link",
        json={
            "book_id": "book-1",
            "notebook_id": "notebook-1",
            "notebook_title": "Notebook One",
            "title": "Book One",
            "source_id": "source-1",
            "linked_at": "2026-05-26T00:00:00Z",
        },
    )

    assert link_response.status_code == 200
    assert link_response.json()["book"]["notebook_id"] == "notebook-1"

    get_response = client.get("/books/book-1")

    assert get_response.status_code == 200
    assert get_response.json()["book"]["source_id"] == "source-1"
    assert get_response.json()["book"]["notebook_title"] == "Notebook One"


def test_book_get_returns_404_for_missing_mapping(tmp_path):
    app = create_app(BridgeConfig(adapter="mock", data_dir=tmp_path))
    client = TestClient(app)

    response = client.get("/books/missing")

    assert response.status_code == 404


def test_book_delete_clears_mapping(tmp_path):
    app = create_app(BridgeConfig(adapter="mock", data_dir=tmp_path))
    client = TestClient(app)

    client.post(
        "/books/link",
        json={
            "book_id": "book-1",
            "notebook_id": "notebook-1",
            "notebook_title": "Notebook One",
            "title": "Book One",
        },
    )

    delete_response = client.delete("/books/book-1")

    assert delete_response.status_code == 200
    assert delete_response.json() == {"ok": True, "deleted": True}
    assert client.get("/books/book-1").status_code == 404
