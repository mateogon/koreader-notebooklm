"""Auth broker endpoint tests."""

from pathlib import Path
from types import SimpleNamespace

from fastapi.testclient import TestClient

from koreader_notebooklm_bridge.app import create_app
from koreader_notebooklm_bridge.auth_broker.store import AuthBrokerStore
from koreader_notebooklm_bridge.config import BridgeConfig


def test_auth_session_creation_has_pairing_code_and_no_secrets():
    client = TestClient(create_app(BridgeConfig()))

    response = client.post("/auth/sessions")

    assert response.status_code == 200
    body = response.json()
    assert body["session_id"]
    assert len(body["pairing_code"]) == 6
    assert "browser_url" in body
    assert "cookies" not in body
    assert "csrf_token" not in body


def test_auth_session_status_rejects_unknown_session():
    client = TestClient(create_app(BridgeConfig()))

    response = client.get("/auth/sessions/missing")

    assert response.status_code == 404


def test_auth_login_rejects_bad_pairing_code():
    client = TestClient(create_app(BridgeConfig()))
    session = client.post("/auth/sessions").json()

    response = client.post(f"/auth/sessions/{session['session_id']}/login?code=000000")

    assert response.status_code == 403


def test_auth_bundle_waits_until_login_ready():
    client = TestClient(create_app(BridgeConfig()))
    session = client.post("/auth/sessions").json()

    response = client.get(
        f"/auth/sessions/{session['session_id']}/bundle?code={session['pairing_code']}"
    )

    assert response.status_code == 425


def test_auth_login_makes_bundle_downloadable(monkeypatch, tmp_path):
    import koreader_notebooklm_bridge.auth_broker.routes as routes

    def fake_login_with_browser(**kwargs):
        output_path = Path(kwargs["output_path"])
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(
            '{"base_url":"https://notebooklm.google.com","cookies":[{"name":"SID","value":"secret"}],"csrf_token":"token"}',
            encoding="utf-8",
        )
        return SimpleNamespace(
            bundle_path=output_path,
            profile="test",
            cookie_count=1,
            email="user@example.com",
        )

    monkeypatch.setattr(routes, "login_with_browser", fake_login_with_browser)

    client = TestClient(create_app(BridgeConfig(data_dir=tmp_path)))
    session = client.post("/auth/sessions").json()
    login = client.post(
        f"/auth/sessions/{session['session_id']}/login?code={session['pairing_code']}"
    )

    assert login.status_code == 200
    status = client.get(f"/auth/sessions/{session['session_id']}").json()
    assert status["status"] == "ready"

    bundle = client.get(
        f"/auth/sessions/{session['session_id']}/bundle?code={session['pairing_code']}"
    )

    assert bundle.status_code == 200
    assert bundle.json()["csrf_token"] == "token"


def test_auth_session_expires():
    app = create_app(BridgeConfig())
    app.state.auth_broker = AuthBrokerStore(ttl_seconds=-1)
    client = TestClient(app)
    session = client.post("/auth/sessions").json()

    response = client.get(f"/auth/sessions/{session['session_id']}")

    assert response.status_code == 200
    assert response.json()["status"] == "expired"
