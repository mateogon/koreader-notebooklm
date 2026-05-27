#!/usr/bin/env python3
"""Export an nlm auth profile to a portable nlm-lite auth bundle."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "bridge" / "src"))

from koreader_notebooklm_bridge.notebooklm_lite.auth import (  # noqa: E402
    AuthBundleError,
    export_nlm_auth_bundle,
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Export local nlm cookies/tokens to an nlm-lite auth bundle."
    )
    parser.add_argument("--profile", default="default", help="nlm profile to export")
    parser.add_argument(
        "--output",
        type=Path,
        help=(
            "output JSON path. Defaults to "
            "~/.notebooklm-mcp-cli/auth-bundles/<profile>-auth-bundle.json"
        ),
    )
    parser.add_argument(
        "--base-url",
        default="https://notebooklm.google.com",
        help="NotebookLM base URL",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="overwrite an existing bundle",
    )
    parser.add_argument(
        "--allow-repo-output",
        action="store_true",
        help="allow writing the auth bundle inside this repository",
    )
    args = parser.parse_args()

    output = args.output or (
        Path.home()
        / ".notebooklm-mcp-cli"
        / "auth-bundles"
        / f"{args.profile}-auth-bundle.json"
    )
    output = output.expanduser().resolve()

    if not args.allow_repo_output and _is_relative_to(output, REPO_ROOT):
        print(
            "Refusing to write an auth bundle inside the repository. "
            "Use an output path outside the repo or pass --allow-repo-output.",
            file=sys.stderr,
        )
        return 2

    try:
        written = export_nlm_auth_bundle(
            profile=args.profile,
            output_path=output,
            base_url=args.base_url,
            overwrite=args.overwrite,
        )
    except AuthBundleError as e:
        print(f"Auth export failed: {e}", file=sys.stderr)
        return 1

    print("Auth bundle exported.")
    print(f"  profile: {args.profile}")
    print(f"  output:  {written}")
    print("  mode:    0600")
    print()
    print("Use it with:")
    print(f"  KOREADER_NOTEBOOKLM_AUTH_BUNDLE={written}")
    return 0


def _is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


if __name__ == "__main__":
    raise SystemExit(main())
