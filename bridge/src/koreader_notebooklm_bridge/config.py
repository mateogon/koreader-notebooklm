"""Configuration for the local bridge."""

from dataclasses import dataclass
import os
from pathlib import Path


@dataclass(frozen=True)
class BridgeConfig:
    host: str = "127.0.0.1"
    port: int = 8765
    adapter: str = "mock"
    default_notebook_id: str | None = None
    nlm_command: str = "nlm"
    nlm_profile: str | None = None
    nlm_timeout_seconds: float = 120.0
    auth_bundle_path: Path | None = None
    notebooklm_base_url: str = "https://notebooklm.google.com"
    direct_timeout_seconds: float = 120.0
    upload_wait_seconds: float = 600.0
    data_dir: Path = Path("data")


def load_config() -> BridgeConfig:
    return BridgeConfig(
        host=os.getenv("KOREADER_NOTEBOOKLM_HOST", "127.0.0.1"),
        port=int(os.getenv("KOREADER_NOTEBOOKLM_PORT", "8765")),
        adapter=os.getenv("KOREADER_NOTEBOOKLM_ADAPTER", "mock"),
        default_notebook_id=os.getenv("KOREADER_NOTEBOOKLM_DEFAULT_NOTEBOOK_ID"),
        nlm_command=os.getenv("KOREADER_NOTEBOOKLM_NLM_COMMAND", "nlm"),
        nlm_profile=os.getenv("KOREADER_NOTEBOOKLM_NLM_PROFILE"),
        nlm_timeout_seconds=float(os.getenv("KOREADER_NOTEBOOKLM_NLM_TIMEOUT_SECONDS", "120")),
        auth_bundle_path=(
            Path(value) if (value := os.getenv("KOREADER_NOTEBOOKLM_AUTH_BUNDLE")) else None
        ),
        notebooklm_base_url=os.getenv(
            "KOREADER_NOTEBOOKLM_BASE_URL", "https://notebooklm.google.com"
        ).rstrip("/"),
        direct_timeout_seconds=float(
            os.getenv("KOREADER_NOTEBOOKLM_DIRECT_TIMEOUT_SECONDS", "120")
        ),
        upload_wait_seconds=float(os.getenv("KOREADER_NOTEBOOKLM_UPLOAD_WAIT_SECONDS", "600")),
        data_dir=Path(os.getenv("KOREADER_NOTEBOOKLM_DATA_DIR", "data")),
    )
