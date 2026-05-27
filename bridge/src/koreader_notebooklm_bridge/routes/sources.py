"""Source routes."""

from io import BytesIO
from pathlib import Path
from uuid import uuid4
from zipfile import BadZipFile, ZipFile

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile

from ..adapters.base import NotebookLMAdapter
from ..adapters.errors import AdapterError
from ..models import SourceUploadRequest, SourceUploadResponse
from ..services.sources import upload_source
from .dependencies import get_adapter

router = APIRouter()


def _infer_extension(content: bytes) -> str | None:
    if content.startswith(b"%PDF"):
        return ".pdf"
    if content.startswith(b"PK"):
        try:
            with ZipFile(BytesIO(content)) as archive:
                mimetype = archive.read("mimetype").strip()
        except (BadZipFile, KeyError):
            return None
        if mimetype == b"application/epub+zip":
            return ".epub"
    return None


def _upload_filename(filename: str | None, content: bytes) -> str:
    safe_name = Path(filename or "source").name or "source"
    if Path(safe_name).suffix:
        return safe_name
    return safe_name + (_infer_extension(content) or "")


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
    content = await file.read()
    filename = _upload_filename(file.filename, content)
    upload_dir = request.app.state.config.data_dir / "uploads"
    upload_dir.mkdir(parents=True, exist_ok=True)
    saved_path = upload_dir / f"{uuid4().hex}-{filename}"
    saved_path.write_bytes(content)

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
