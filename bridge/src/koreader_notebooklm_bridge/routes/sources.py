"""Source routes."""

from fastapi import APIRouter, Depends, HTTPException

from ..adapters.base import NotebookLMAdapter
from ..adapters.errors import AdapterError
from ..models import SourceUploadRequest, SourceUploadResponse
from ..services.sources import upload_source
from .dependencies import get_adapter

router = APIRouter()


@router.post("/sources/upload", response_model=SourceUploadResponse)
def post_source_upload(
    request: SourceUploadRequest,
    adapter: NotebookLMAdapter = Depends(get_adapter),
) -> SourceUploadResponse:
    try:
        return upload_source(adapter, request)
    except AdapterError as e:
        raise HTTPException(status_code=502, detail=str(e)) from e
