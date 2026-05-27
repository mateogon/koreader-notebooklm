"""Ask route."""

import logging

from fastapi import APIRouter, Depends, HTTPException

from ..adapters.base import NotebookLMAdapter
from ..adapters.errors import AdapterError, AdapterNotConfiguredError
from ..models import AskRequest, AskResponse
from ..services.ask import ask_notebook
from .dependencies import get_adapter

router = APIRouter()
logger = logging.getLogger("uvicorn.error")


@router.post("/ask", response_model=AskResponse)
def ask(
    request: AskRequest,
    adapter: NotebookLMAdapter = Depends(get_adapter),
) -> AskResponse:
    logger.info(
        "Bridge /ask adapter=%s notebook_id=%s selected_chars=%s prompt_chars=%s",
        getattr(adapter, "name", "unknown"),
        request.notebook_id,
        len(request.selected_text or ""),
        len(request.prompt or ""),
    )
    try:
        return ask_notebook(adapter, request)
    except AdapterNotConfiguredError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except AdapterError as e:
        raise HTTPException(status_code=502, detail=str(e)) from e
