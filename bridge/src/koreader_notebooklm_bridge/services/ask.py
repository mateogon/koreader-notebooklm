"""Ask service."""

from ..adapters.base import NotebookLMAdapter
from ..models import AskRequest, AskResponse


def ask_notebook(adapter: NotebookLMAdapter, request: AskRequest) -> AskResponse:
    return adapter.ask(request)
