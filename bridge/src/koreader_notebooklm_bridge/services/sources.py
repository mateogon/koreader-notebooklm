"""Source service."""

from ..adapters.base import NotebookLMAdapter
from ..models import SourceUploadRequest, SourceUploadResponse


def upload_source(
    adapter: NotebookLMAdapter,
    request: SourceUploadRequest,
) -> SourceUploadResponse:
    return adapter.upload_source(request)
