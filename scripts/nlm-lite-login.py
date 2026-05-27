#!/usr/bin/env python3
"""Create an nlm-lite auth bundle without using nlm."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import sys

REPO_ROOT = Path(__file__).resolve().parents[1]
if os.environ.get("KOREADER_NOTEBOOKLM_UV_REEXEC") != "1":
    try:
        import websocket  # noqa: F401
    except ModuleNotFoundError:
        uv = shutil.which("uv")
        if uv:
            env = os.environ.copy()
            env["KOREADER_NOTEBOOKLM_UV_REEXEC"] = "1"
            os.execve(
                uv,
                [
                    uv,
                    "run",
                    "--project",
                    str(REPO_ROOT / "bridge"),
                    "python",
                    str(Path(__file__).resolve()),
                    *sys.argv[1:],
                ],
                env,
            )

sys.path.insert(0, str(REPO_ROOT / "bridge" / "src"))

from koreader_notebooklm_bridge.notebooklm_lite.login import (  # noqa: E402
    BrowserAuthError,
    default_auth_bundle_path,
    login_with_browser,
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Launch Chrome, authenticate with NotebookLM, and write an nlm-lite auth bundle."
    )
    parser.add_argument("--profile", default="default", help="local nlm-lite auth profile name")
    parser.add_argument("--output", type=Path, help="output auth bundle path")
    parser.add_argument("--base-url", default="https://notebooklm.google.com")
    parser.add_argument("--timeout", type=int, default=300, help="login timeout in seconds")
    parser.add_argument("--chrome-path", type=Path, help="explicit Chrome executable path")
    parser.add_argument("--chrome-profile-dir", type=Path, help="explicit Chrome user-data-dir")
    parser.add_argument("--overwrite", action="store_true", help="overwrite existing bundle")
    parser.add_argument("--keep-browser-open", action="store_true", help="leave Chrome open")
    parser.add_argument(
        "--allow-repo-output",
        action="store_true",
        help="allow writing the auth bundle inside this repository",
    )
    args = parser.parse_args()

    output = (args.output or default_auth_bundle_path(args.profile)).expanduser().resolve()
    if not args.allow_repo_output and _is_relative_to(output, REPO_ROOT):
        print(
            "Refusing to write an auth bundle inside the repository. "
            "Use an output path outside the repo or pass --allow-repo-output.",
            file=sys.stderr,
        )
        return 2

    print("Launching Chrome for nlm-lite auth.")
    print("Sign in to NotebookLM in the browser window if prompted.")
    print()

    try:
        result = login_with_browser(
            profile=args.profile,
            output_path=output,
            base_url=args.base_url,
            timeout_seconds=args.timeout,
            chrome_path=args.chrome_path,
            chrome_profile_dir=args.chrome_profile_dir,
            overwrite=args.overwrite,
            keep_browser_open=args.keep_browser_open,
        )
    except BrowserAuthError as e:
        print(f"nlm-lite login failed: {e}", file=sys.stderr)
        return 1

    print("nlm-lite auth bundle created.")
    print(f"  profile: {result.profile}")
    print(f"  output:  {result.bundle_path}")
    print(f"  cookies: {result.cookie_count}")
    if result.email:
        print(f"  account: {result.email}")
    print()
    print("Use it with:")
    print(f"  KOREADER_NOTEBOOKLM_AUTH_BUNDLE={result.bundle_path}")
    return 0


def _is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


if __name__ == "__main__":
    raise SystemExit(main())
