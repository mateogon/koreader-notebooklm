"""Auth bundle loading and page-token refresh for nlm-lite.

This module reads existing local NotebookLM auth state. It does not implement
Google login and must never log cookie values.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
import json
from pathlib import Path
import re
import time
from typing import Any

import httpx

from .errors import AuthBundleError

DEFAULT_BASE_URL = "https://notebooklm.google.com"
STORAGE_DIR_NAME = ".notebooklm-mcp-cli"

PAGE_FETCH_HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Sec-Fetch-Dest": "document",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-Site": "none",
    "Sec-Fetch-User": "?1",
}


@dataclass(frozen=True)
class AuthBundle:
    cookies: dict[str, str] | list[dict[str, Any]]
    csrf_token: str = ""
    session_id: str = ""
    build_label: str = ""
    extracted_at: float = 0.0
    base_url: str = DEFAULT_BASE_URL

    def require_cookies(self) -> None:
        if not self.cookies:
            raise AuthBundleError(
                "auth_missing",
                "NotebookLM auth cookies are missing. Run nlm login or provide an auth bundle.",
            )

    def with_page_tokens(self, tokens: "PageTokens") -> "AuthBundle":
        return replace(
            self,
            csrf_token=tokens.csrf_token,
            session_id=tokens.session_id,
            build_label=tokens.build_label,
            extracted_at=time.time(),
        )


@dataclass(frozen=True)
class PageTokens:
    csrf_token: str
    session_id: str = ""
    build_label: str = ""


def load_auth_bundle(
    *,
    bundle_path: Path | None = None,
    profile: str | None = None,
    base_url: str = DEFAULT_BASE_URL,
) -> AuthBundle:
    """Load explicit auth first, then local nlm profile/cache."""

    if bundle_path:
        return _load_explicit_bundle(bundle_path, base_url=base_url)

    loaded = _load_nlm_profile(profile or "default", base_url=base_url)
    if loaded:
        return loaded

    loaded = _load_legacy_auth_cache(base_url=base_url)
    if loaded:
        return loaded

    raise AuthBundleError(
        "auth_missing",
        "NotebookLM auth bundle was not found. Run nlm login or set KOREADER_NOTEBOOKLM_AUTH_BUNDLE.",
    )


def refresh_page_tokens(
    bundle: AuthBundle,
    *,
    timeout: float = 15.0,
    transport: httpx.BaseTransport | None = None,
) -> AuthBundle:
    """Refresh CSRF/session/build-label values by fetching the NotebookLM page."""

    bundle.require_cookies()
    cookies = to_httpx_cookies(bundle.cookies)
    try:
        with httpx.Client(
            cookies=cookies,
            headers=PAGE_FETCH_HEADERS,
            follow_redirects=True,
            timeout=timeout,
            transport=transport,
        ) as client:
            response = client.get(f"{bundle.base_url}/")
    except httpx.HTTPError as e:
        raise AuthBundleError(
            "auth_expired",
            "Could not refresh NotebookLM auth tokens.",
            debug=e.__class__.__name__,
        ) from e

    if "accounts.google.com" in str(response.url):
        raise AuthBundleError(
            "auth_expired",
            "NotebookLM auth expired. Re-authenticate on Mac/Windows and re-export auth.",
            status_code=response.status_code,
        )
    if response.status_code != 200:
        raise AuthBundleError(
            "auth_expired",
            f"Could not refresh NotebookLM auth tokens: HTTP {response.status_code}.",
            status_code=response.status_code,
        )

    tokens = extract_page_tokens(response.text)
    return bundle.with_page_tokens(tokens)


def extract_page_tokens(html: str) -> PageTokens:
    csrf_token = _first_match(
        html,
        [
            r'"SNlM0e":"([^"]+)"',
            r"at=([^&\"]+)",
            r'"FdrFJe":"([^"]+)"',
        ],
    )
    if not csrf_token:
        raise AuthBundleError(
            "notebooklm_changed",
            "Could not extract NotebookLM CSRF token from page.",
        )

    return PageTokens(
        csrf_token=csrf_token,
        session_id=_first_match(html, [r'"FdrFJe":"([^"]+)"']) or "",
        build_label=_first_match(html, [r'"cfb2h":"([^"]+)"']) or "",
    )


def to_httpx_cookies(cookies_data: dict[str, str] | list[dict[str, Any]]) -> httpx.Cookies:
    cookies = httpx.Cookies()
    if isinstance(cookies_data, list):
        for item in cookies_data:
            name = item.get("name")
            value = item.get("value")
            domain = item.get("domain")
            path = item.get("path", "/")
            if isinstance(name, str) and isinstance(value, str):
                cookies.set(name, value, domain=domain, path=path)
                if domain == ".google.com":
                    cookies.set(name, value, domain=".googleusercontent.com", path=path)
        return cookies

    for name, value in cookies_data.items():
        if isinstance(name, str) and isinstance(value, str):
            cookies.set(name, value, domain=".google.com")
            cookies.set(name, value, domain=".googleusercontent.com")
    return cookies


def _load_explicit_bundle(path: Path, *, base_url: str) -> AuthBundle:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as e:
        raise AuthBundleError(
            "auth_missing",
            f"NotebookLM auth bundle does not exist: {path}",
        ) from e
    except json.JSONDecodeError as e:
        raise AuthBundleError(
            "parse_error",
            "NotebookLM auth bundle is not valid JSON.",
        ) from e
    return _bundle_from_mapping(data, base_url=base_url)


def _load_nlm_profile(profile: str, *, base_url: str) -> AuthBundle | None:
    profile_dir = _storage_dir() / "profiles" / profile
    cookies_path = profile_dir / "cookies.json"
    metadata_path = profile_dir / "metadata.json"
    if not cookies_path.exists():
        return None
    try:
        cookies = json.loads(cookies_path.read_text(encoding="utf-8"))
        metadata = (
            json.loads(metadata_path.read_text(encoding="utf-8")) if metadata_path.exists() else {}
        )
    except (OSError, json.JSONDecodeError):
        return None

    return AuthBundle(
        cookies=cookies,
        csrf_token=str(metadata.get("csrf_token") or ""),
        session_id=str(metadata.get("session_id") or ""),
        build_label=str(metadata.get("build_label") or ""),
        extracted_at=time.time(),
        base_url=base_url,
    )


def _load_legacy_auth_cache(*, base_url: str) -> AuthBundle | None:
    path = _storage_dir() / "auth.json"
    if not path.exists():
        return None
    try:
        return _bundle_from_mapping(json.loads(path.read_text(encoding="utf-8")), base_url=base_url)
    except (OSError, json.JSONDecodeError, AuthBundleError):
        return None


def _bundle_from_mapping(data: object, *, base_url: str) -> AuthBundle:
    if not isinstance(data, dict):
        raise AuthBundleError("parse_error", "NotebookLM auth bundle must be a JSON object.")
    cookies = data.get("cookies")
    if not isinstance(cookies, (dict, list)):
        raise AuthBundleError("auth_missing", "NotebookLM auth bundle has no cookies.")
    return AuthBundle(
        cookies=cookies,
        csrf_token=str(data.get("csrf_token") or ""),
        session_id=str(data.get("session_id") or ""),
        build_label=str(data.get("build_label") or ""),
        extracted_at=float(data.get("extracted_at") or 0),
        base_url=str(data.get("base_url") or base_url).rstrip("/"),
    )


def _storage_dir() -> Path:
    return Path.home() / STORAGE_DIR_NAME


def _first_match(value: str, patterns: list[str]) -> str | None:
    for pattern in patterns:
        match = re.search(pattern, value)
        if match:
            return match.group(1)
    return None
