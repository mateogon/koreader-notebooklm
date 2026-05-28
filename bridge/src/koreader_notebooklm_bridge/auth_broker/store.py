"""In-memory auth broker sessions.

Auth bundles are treated as credentials. This store keeps only paths and small
metadata in memory; routes decide when bundle contents may be returned.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path
import secrets


DEFAULT_SESSION_TTL_SECONDS = 600


@dataclass
class AuthSession:
    session_id: str
    pairing_code: str
    expires_at: datetime
    browser_url: str
    status: str = "pending"
    message: str = "Open the browser URL on your phone or Mac."
    bundle_path: Path | None = None
    metadata: dict[str, str | int] = field(default_factory=dict)

    def expired(self, now: datetime | None = None) -> bool:
        return (now or datetime.now(UTC)) >= self.expires_at

    def public_status(self) -> dict[str, str]:
        if self.expired() and self.status not in {"downloaded", "failed"}:
            self.status = "expired"
            self.message = "Auth session expired. Start a new refresh."
        return {
            "status": self.status,
            "message": self.message,
        }


class AuthBrokerStore:
    def __init__(self, *, ttl_seconds: int = DEFAULT_SESSION_TTL_SECONDS) -> None:
        self.ttl_seconds = ttl_seconds
        self._sessions: dict[str, AuthSession] = {}

    def create_session(self, *, browser_base_url: str) -> AuthSession:
        self._prune_expired()
        session_id = secrets.token_urlsafe(9).replace("-", "").replace("_", "")[:12]
        pairing_code = f"{secrets.randbelow(1_000_000):06d}"
        expires_at = datetime.now(UTC) + timedelta(seconds=self.ttl_seconds)
        browser_url = (
            f"{browser_base_url.rstrip('/')}/auth/sessions/{session_id}"
            f"?code={pairing_code}"
        )
        session = AuthSession(
            session_id=session_id,
            pairing_code=pairing_code,
            expires_at=expires_at,
            browser_url=browser_url,
        )
        self._sessions[session_id] = session
        return session

    def get(self, session_id: str) -> AuthSession | None:
        session = self._sessions.get(session_id)
        if session:
            session.public_status()
        return session

    def require(self, session_id: str) -> AuthSession:
        session = self.get(session_id)
        if not session:
            raise KeyError(session_id)
        return session

    def check_pairing_code(self, session: AuthSession, code: str | None) -> bool:
        return bool(code) and secrets.compare_digest(session.pairing_code, str(code))

    def _prune_expired(self) -> None:
        for session_id, session in list(self._sessions.items()):
            if session.expired() and session.status in {"pending", "expired", "failed"}:
                self._sessions.pop(session_id, None)
