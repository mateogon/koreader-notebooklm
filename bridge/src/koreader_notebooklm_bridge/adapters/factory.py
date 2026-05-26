"""Adapter factory."""

from ..config import BridgeConfig
from .base import NotebookLMAdapter
from .errors import AdapterNotConfiguredError
from .mock import MockNotebookLMAdapter
from .notebooklm import NlmNotebookLMAdapter


def create_adapter(config: BridgeConfig) -> NotebookLMAdapter:
    adapter = config.adapter.strip().lower()
    if adapter == "mock":
        return MockNotebookLMAdapter()
    if adapter == "nlm":
        return NlmNotebookLMAdapter(config)
    raise AdapterNotConfiguredError(f"Unknown adapter: {config.adapter}")
