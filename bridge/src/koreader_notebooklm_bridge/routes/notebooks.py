"""Notebook routes."""

from fastapi import APIRouter, Depends, HTTPException

from ..adapters.base import NotebookLMAdapter
from ..adapters.errors import AdapterError
from ..models import NotebookCreateRequest, NotebookCreateResponse, NotebookListResponse
from ..services.notebooks import create_notebook, list_notebooks
from .dependencies import get_adapter

router = APIRouter()


@router.get("/notebooks", response_model=NotebookListResponse)
def get_notebooks(adapter: NotebookLMAdapter = Depends(get_adapter)) -> NotebookListResponse:
    try:
        return NotebookListResponse(notebooks=list_notebooks(adapter))
    except AdapterError as e:
        raise HTTPException(status_code=502, detail=str(e)) from e


@router.post("/notebooks", response_model=NotebookCreateResponse)
def post_notebook(
    request: NotebookCreateRequest,
    adapter: NotebookLMAdapter = Depends(get_adapter),
) -> NotebookCreateResponse:
    try:
        return create_notebook(adapter, request.title)
    except AdapterError as e:
        raise HTTPException(status_code=502, detail=str(e)) from e
