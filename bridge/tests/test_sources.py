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


def test_source_upload_file_returns_mock_source(tmp_path):
    from koreader_notebooklm_bridge.app import create_app
    from koreader_notebooklm_bridge.config import BridgeConfig

    client = TestClient(create_app(BridgeConfig(adapter="mock", data_dir=tmp_path)))

    response = client.post(
        "/sources/upload-file",
        data={
            "notebook_id": "mock-notebook",
            "title": "Uploaded EPUB",
            "wait": "true",
        },
        files={
            "file": ("book.epub", b"fake epub content", "application/epub+zip"),
        },
    )

    assert response.status_code == 200
    assert response.json() == {
        "ok": True,
        "source_id": "mock-source",
        "title": "Uploaded EPUB",
        "notebook_id": "mock-notebook",
        "adapter": "mock",
    }
    saved_files = list((tmp_path / "uploads").glob("*-book.epub"))
    assert len(saved_files) == 1
    assert saved_files[0].read_bytes() == b"fake epub content"
