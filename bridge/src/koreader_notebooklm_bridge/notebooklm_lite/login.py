"""Standalone browser auth bootstrap for nlm-lite.

This module intentionally does not import or call notebooklm-mcp-cli. It uses a
temporary Chrome DevTools Protocol session to let the user sign in, then writes a
portable auth bundle that the nlm-lite adapter can read.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import platform
import shutil
import socket
import subprocess
import time
from typing import Any
from urllib.parse import quote, urlparse

import httpx
import websocket

from .auth import DEFAULT_BASE_URL, extract_page_tokens, write_auth_bundle
from .errors import AuthBundleError


@dataclass(frozen=True)
class BrowserAuthResult:
    bundle_path: Path
    profile: str
    cookie_count: int
    email: str = ""


class BrowserAuthError(AuthBundleError):
    """Raised when standalone browser auth cannot complete."""


def login_with_browser(
    *,
    profile: str = "default",
    output_path: Path,
    base_url: str = DEFAULT_BASE_URL,
    timeout_seconds: int = 300,
    chrome_path: Path | None = None,
    chrome_profile_dir: Path | None = None,
    overwrite: bool = False,
    keep_browser_open: bool = False,
) -> BrowserAuthResult:
    base_url = base_url.rstrip("/")
    chrome = chrome_path or find_chrome_path()
    if chrome is None:
        raise BrowserAuthError(
            "auth_missing",
            "Chrome was not found. Install Chrome or pass --chrome-path.",
        )

    port = find_available_port()
    user_data_dir = chrome_profile_dir or default_chrome_profile_dir(profile)
    user_data_dir.mkdir(parents=True, exist_ok=True)
    process = launch_chrome(chrome, user_data_dir, port, base_url)

    try:
        cdp_base = wait_for_cdp(port, timeout_seconds=30)
        page = find_or_create_notebooklm_page(cdp_base, base_url)
        ws_url = page.get("webSocketDebuggerUrl")
        if not isinstance(ws_url, str) or not ws_url:
            raise BrowserAuthError("auth_failed", "Chrome did not expose a page WebSocket URL.")

        html, current_url = wait_for_notebooklm_login(ws_url, timeout_seconds=timeout_seconds)
        tokens = extract_page_tokens(html)
        cookies = get_all_cookies(ws_url)
        if not cookies:
            raise BrowserAuthError("auth_missing", "Chrome did not return NotebookLM cookies.")

        bundle = {
            "schema": "koreader-notebooklm-auth-bundle/v1",
            "provider": "nlm-lite-browser-login",
            "profile": profile,
            "base_url": base_url,
            "cookies": cookies,
            "csrf_token": tokens.csrf_token,
            "session_id": tokens.session_id,
            "build_label": tokens.build_label,
            "email": extract_email(html),
            "login_url": current_url,
            "extracted_at": time.time(),
        }
        written = write_auth_bundle(bundle, output_path=output_path, overwrite=overwrite)
        return BrowserAuthResult(
            bundle_path=written,
            profile=profile,
            cookie_count=len(cookies),
            email=str(bundle.get("email") or ""),
        )
    finally:
        if not keep_browser_open:
            terminate_chrome(process)


def default_storage_dir() -> Path:
    return Path.home() / ".koreader-notebooklm"


def default_chrome_profile_dir(profile: str) -> Path:
    return default_storage_dir() / "chrome-profiles" / profile


def default_auth_bundle_path(profile: str) -> Path:
    return default_storage_dir() / "auth-bundles" / f"{profile}-auth-bundle.json"


def find_chrome_path() -> Path | None:
    system = platform.system()
    candidates: list[Path] = []
    if system == "Darwin":
        candidates.extend(
            [
                Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
                Path.home()
                / "Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                Path("/Applications/Chromium.app/Contents/MacOS/Chromium"),
            ]
        )
    elif system == "Windows":
        for root in (
            os.environ.get("PROGRAMFILES"),
            os.environ.get("PROGRAMFILES(X86)"),
            os.environ.get("LOCALAPPDATA"),
        ):
            if root:
                candidates.append(Path(root) / "Google/Chrome/Application/chrome.exe")
    else:
        for command in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser"):
            found = shutil.which(command)
            if found:
                candidates.append(Path(found))

    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None


def find_available_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def launch_chrome(
    chrome_path: Path,
    user_data_dir: Path,
    port: int,
    base_url: str,
) -> subprocess.Popen[bytes]:
    args = [
        str(chrome_path),
        f"--remote-debugging-port={port}",
        f"--user-data-dir={user_data_dir}",
        f"--remote-allow-origins=http://127.0.0.1:{port}",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-extensions",
        base_url,
    ]
    return subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def terminate_chrome(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()


def wait_for_cdp(port: int, *, timeout_seconds: int = 30) -> str:
    base = f"http://127.0.0.1:{port}"
    deadline = time.time() + timeout_seconds
    with httpx.Client(trust_env=False, timeout=5.0) as client:
        while time.time() < deadline:
            try:
                response = client.get(f"{base}/json/version")
                if response.status_code == 200:
                    return base
            except httpx.HTTPError:
                pass
            time.sleep(1)
    raise BrowserAuthError("auth_failed", "Chrome DevTools did not become ready.")


def find_or_create_notebooklm_page(cdp_base: str, base_url: str) -> dict[str, Any]:
    with httpx.Client(trust_env=False, timeout=10.0) as client:
        response = client.get(f"{cdp_base}/json")
        pages = response.json() if response.status_code == 200 else []
        for page in pages:
            if _is_notebooklm_url(str(page.get("url") or "")):
                return page

        response = client.put(f"{cdp_base}/json/new?{quote(base_url + '/', safe='')}")
        if response.status_code == 200 and response.text.strip():
            return response.json()

        response = client.put(f"{cdp_base}/json/new")
        if response.status_code == 200 and response.text.strip():
            page = response.json()
            ws_url = page.get("webSocketDebuggerUrl")
            if isinstance(ws_url, str):
                execute_cdp_command(ws_url, "Page.enable")
                execute_cdp_command(ws_url, "Page.navigate", {"url": base_url + "/"})
            return page

    raise BrowserAuthError("auth_failed", "Could not open a NotebookLM browser page.")


def wait_for_notebooklm_login(ws_url: str, *, timeout_seconds: int) -> tuple[str, str]:
    deadline = time.time() + timeout_seconds
    last_url = ""
    while time.time() < deadline:
        current_url = get_current_url(ws_url)
        last_url = current_url or last_url
        if _is_logged_in_notebooklm_url(current_url):
            html = get_page_html(ws_url)
            try:
                extract_page_tokens(html)
                return html, current_url
            except AuthBundleError:
                pass
        time.sleep(2)
    raise BrowserAuthError(
        "auth_failed",
        f"Timed out waiting for NotebookLM login. Last URL: {last_url}",
    )


def execute_cdp_command(ws_url: str, method: str, params: dict[str, Any] | None = None) -> dict:
    command = {"id": 1, "method": method, "params": params or {}}
    with _without_proxy_env():
        ws = websocket.create_connection(_normalize_ws_url(ws_url), timeout=30, suppress_origin=True)
    try:
        ws.send(json.dumps(command))
        ws.settimeout(30)
        while True:
            response = json.loads(ws.recv())
            if response.get("id") == 1:
                return response.get("result", {})
    finally:
        ws.close()


def get_current_url(ws_url: str) -> str:
    execute_cdp_command(ws_url, "Runtime.enable")
    result = execute_cdp_command(
        ws_url,
        "Runtime.evaluate",
        {"expression": "window.location.href", "returnByValue": True},
    )
    return str(result.get("result", {}).get("value") or "")


def get_page_html(ws_url: str) -> str:
    execute_cdp_command(ws_url, "Runtime.enable")
    result = execute_cdp_command(
        ws_url,
        "Runtime.evaluate",
        {"expression": "document.documentElement.outerHTML", "returnByValue": True},
    )
    return str(result.get("result", {}).get("value") or "")


def get_all_cookies(ws_url: str) -> list[dict[str, Any]]:
    result = execute_cdp_command(ws_url, "Network.getAllCookies")
    cookies = result.get("cookies")
    return cookies if isinstance(cookies, list) else []


def extract_email(html: str) -> str:
    import re

    patterns = [
        r'"oPEP7c":"([^"]+@[^"]+)"',
        r'data-email="([^"]+)"',
        r'"([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})"',
    ]
    for pattern in patterns:
        for match in re.findall(pattern, html):
            if "@google.com" not in match and "@gstatic" not in match:
                return match
    return ""


def _is_notebooklm_url(url: str) -> bool:
    return "notebooklm.google.com" in url or "notebooklm.cloud.google.com" in url


def _is_logged_in_notebooklm_url(url: str) -> bool:
    try:
        host = (urlparse(url).hostname or "").lower()
    except Exception:
        return False
    if host == "accounts.google.com" or host.endswith(".accounts.google.com"):
        return False
    return _is_notebooklm_url(url)


def _normalize_ws_url(url: str) -> str:
    return url.replace("://localhost:", "://127.0.0.1:")


class _without_proxy_env:
    keys = (
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "http_proxy",
        "https_proxy",
        "all_proxy",
    )

    def __enter__(self) -> None:
        self.saved = {key: os.environ.pop(key) for key in self.keys if key in os.environ}

    def __exit__(self, exc_type: object, exc: object, tb: object) -> None:
        for key, value in self.saved.items():
            os.environ[key] = value
