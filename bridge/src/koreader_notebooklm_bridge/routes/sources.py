"""Source routes."""

from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile

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


@router.post("/sources/upload-file", response_model=SourceUploadResponse)
async def post_source_upload_file(
    request: Request,
    notebook_id: str = Form(...),
    title: str | None = Form(None),
    wait: bool = Form(True),
    file: UploadFile = File(...),
    adapter: NotebookLMAdapter = Depends(get_adapter),
) -> SourceUploadResponse:
    filename = Path(file.filename or "source").name
    upload_dir = request.app.state.config.data_dir / "uploads"
    upload_dir.mkdir(parents=True, exist_ok=True)
    saved_path = upload_dir / f"{uuid4().hex}-{filename}"
    saved_path.write_bytes(await file.read())

    try:
        return upload_source(
            adapter,
            SourceUploadRequest(
                notebook_id=notebook_id,
                file_path=str(saved_path),
                title=title or filename,
                wait=wait,
            ),
        )
    except AdapterError as e:
        raise HTTPException(status_code=502, detail=str(e)) from e
