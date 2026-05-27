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


def test_ask_job_returns_mock_response():
    client = TestClient(app)

    response = client.post(
        "/ask/jobs",
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
    assert body["job_id"]
    assert body["status"] in {"queued", "running", "succeeded"}

    job = _wait_for_job(client, body["job_id"])
    assert job["status"] == "succeeded"
    assert job["result"]["notebook_id"] == "mock-notebook"
    assert "Explain this simply." in job["result"]["answer"]


def test_ask_job_not_found():
    client = TestClient(app)

    response = client.get("/ask/jobs/missing")

    assert response.status_code == 404


def _wait_for_job(client: TestClient, job_id: str) -> dict:
    for _ in range(20):
        response = client.get(f"/ask/jobs/{job_id}")
        assert response.status_code == 200
        body = response.json()
        if body["status"] in {"succeeded", "failed"}:
            return body
    raise AssertionError("ask job did not finish")
