"""FastAPI routes for the local NotebookLM auth broker."""

from __future__ import annotations

import json
from pathlib import Path
from tempfile import gettempdir

from fastapi import APIRouter, BackgroundTasks, HTTPException, Query, Request
from fastapi.responses import HTMLResponse

from ..notebooklm_lite.errors import AuthBundleError
from ..notebooklm_lite.login import login_with_browser
from .store import AuthBrokerStore, AuthSession


router = APIRouter(prefix="/auth", tags=["auth"])


def _store(request: Request) -> AuthBrokerStore:
    return request.app.state.auth_broker


def _browser_base_url(request: Request) -> str:
    return str(request.base_url).rstrip("/")


def _session_or_404(store: AuthBrokerStore, session_id: str) -> AuthSession:
    try:
        return store.require(session_id)
    except KeyError as e:
        raise HTTPException(status_code=404, detail="Auth session was not found.") from e


def _require_code(store: AuthBrokerStore, session: AuthSession, code: str | None) -> None:
    if session.status == "expired" or session.expired():
        raise HTTPException(status_code=410, detail="Auth session expired.")
    if not store.check_pairing_code(session, code):
        raise HTTPException(status_code=403, detail="Invalid pairing code.")


def _bundle_output_path(session_id: str) -> Path:
    return Path(gettempdir()) / "koreader-notebooklm-auth-broker" / f"{session_id}.json"


@router.post("/sessions")
def create_auth_session(request: Request) -> dict:
    session = _store(request).create_session(browser_base_url=_browser_base_url(request))
    return {
        "session_id": session.session_id,
        "pairing_code": session.pairing_code,
        "expires_at": session.expires_at.isoformat().replace("+00:00", "Z"),
        "browser_url": session.browser_url,
    }


@router.get("/sessions/{session_id}", response_model=None)
def get_auth_session(
    request: Request,
    session_id: str,
    code: str | None = Query(default=None),
):
    store = _store(request)
    session = _session_or_404(store, session_id)
    accept = request.headers.get("accept", "")
    if code and "text/html" in accept and "application/json" not in accept:
        code_ok = store.check_pairing_code(session, code)
        return HTMLResponse(_session_html(session, code, code_ok))
    return session.public_status()


@router.post("/sessions/{session_id}/login", response_model=None)
def start_auth_login(
    request: Request,
    session_id: str,
    background_tasks: BackgroundTasks,
    code: str = Query(...),
):
    store = _store(request)
    session = _session_or_404(store, session_id)
    _require_code(store, session, code)

    if session.status == "ready":
        return _status_or_html(request, session, code)
    if session.status == "login_started":
        return _status_or_html(request, session, code)

    session.status = "login_started"
    session.message = "Chrome login started on the broker host."
    background_tasks.add_task(_run_login, session)
    return _status_or_html(request, session, code)


@router.get("/sessions/{session_id}/bundle")
def download_auth_bundle(
    request: Request,
    session_id: str,
    code: str = Query(...),
) -> dict:
    store = _store(request)
    session = _session_or_404(store, session_id)
    _require_code(store, session, code)

    if session.status == "failed":
        raise HTTPException(status_code=502, detail=session.message)
    if session.status != "ready" or not session.bundle_path:
        raise HTTPException(status_code=425, detail="Auth bundle is not ready yet.")
    if not session.bundle_path.exists():
        raise HTTPException(status_code=404, detail="Auth bundle file was not found.")

    try:
        bundle = json.loads(session.bundle_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        raise HTTPException(status_code=500, detail="Auth bundle could not be read.") from e

    session.status = "downloaded"
    session.message = "Auth bundle downloaded. Save it on the Kindle and complete the session."
    return bundle


@router.post("/sessions/{session_id}/complete")
def complete_auth_session(
    request: Request,
    session_id: str,
    code: str = Query(...),
) -> dict:
    store = _store(request)
    session = _session_or_404(store, session_id)
    _require_code(store, session, code)
    if session.bundle_path and session.bundle_path.exists():
        try:
            session.bundle_path.unlink()
        except OSError:
            pass
    session.status = "downloaded"
    session.message = "Auth refresh complete."
    return session.public_status()


def _run_login(session: AuthSession) -> None:
    try:
        result = login_with_browser(
            profile=f"auth-broker-{session.session_id}",
            output_path=_bundle_output_path(session.session_id),
            timeout_seconds=300,
            overwrite=True,
        )
    except AuthBundleError as e:
        session.status = "failed"
        session.message = e.info.message
        return
    except Exception as e:  # noqa: BLE001 - keep broker failure user-readable.
        session.status = "failed"
        session.message = f"Auth login failed: {e.__class__.__name__}"
        return

    session.bundle_path = result.bundle_path
    session.metadata = {
        "profile": result.profile,
        "cookie_count": result.cookie_count,
        "email": result.email,
    }
    session.status = "ready"
    session.message = "Auth bundle is ready. Return to KOReader and download it."


def _status_or_html(request: Request, session: AuthSession, code: str):
    accept = request.headers.get("accept", "")
    if "text/html" in accept and "application/json" not in accept:
        return HTMLResponse(_session_html(session, code, True))
    return session.public_status()


def _session_html(session: AuthSession, code: str, code_ok: bool) -> str:
    escaped_url = session.browser_url.replace("&", "&amp;").replace("<", "&lt;")
    disabled = "" if code_ok else " disabled"
    warning = "" if code_ok else "<p><strong>Invalid pairing code.</strong></p>"
    return f"""<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>KOReader NotebookLM Auth</title>
<body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 42rem; margin: 2rem auto; padding: 0 1rem;">
<h1>KOReader NotebookLM Auth</h1>
<p>Status: <strong>{session.status}</strong></p>
<p>{session.message}</p>
{warning}
<form method="post" action="/auth/sessions/{session.session_id}/login?code={code}">
  <button{disabled} style="font-size: 1.1rem; padding: .7rem 1rem;">Start login on this Mac</button>
</form>
<p>Pairing URL:</p>
<p style="word-break: break-all;"><code>{escaped_url}</code></p>
<p>This local broker returns the auth bundle only to clients with the pairing code. Do not share this URL.</p>
</body>
</html>"""
