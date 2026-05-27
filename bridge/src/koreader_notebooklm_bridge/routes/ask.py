"""Ask route."""

import logging

from fastapi import APIRouter, Depends, HTTPException

from ..adapters.base import NotebookLMAdapter
from ..adapters.errors import AdapterError, AdapterNotConfiguredError
from ..models import AskJobCreateResponse, AskJobResponse, AskRequest, AskResponse
from ..services.ask import ask_notebook
from ..services.ask_jobs import AskJobStore
from .dependencies import get_adapter, get_ask_jobs

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


@router.post("/ask/jobs", response_model=AskJobCreateResponse)
def create_ask_job(
    request: AskRequest,
    adapter: NotebookLMAdapter = Depends(get_adapter),
    ask_jobs: AskJobStore = Depends(get_ask_jobs),
) -> AskJobCreateResponse:
    logger.info(
        "Bridge /ask/jobs adapter=%s notebook_id=%s selected_chars=%s prompt_chars=%s",
        getattr(adapter, "name", "unknown"),
        request.notebook_id,
        len(request.selected_text or ""),
        len(request.prompt or ""),
    )
    job = ask_jobs.submit(adapter, request)
    return AskJobCreateResponse(job_id=job.job_id, status=job.status)


@router.get("/ask/jobs/{job_id}", response_model=AskJobResponse)
def get_ask_job(
    job_id: str,
    ask_jobs: AskJobStore = Depends(get_ask_jobs),
) -> AskJobResponse:
    try:
        return ask_jobs.get(job_id)
    except KeyError as e:
        raise HTTPException(status_code=404, detail="Ask job not found.") from e
