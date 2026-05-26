"""Health route."""

from fastapi import APIRouter, Depends

from ..adapters.base import NotebookLMAdapter
from ..config import BridgeConfig
from ..models import HealthResponse
from .dependencies import get_adapter, get_config

router = APIRouter()


@router.get("/health", response_model=HealthResponse)
def health(
    adapter: NotebookLMAdapter = Depends(get_adapter),
    config: BridgeConfig = Depends(get_config),
) -> HealthResponse:
    return HealthResponse(adapter=adapter.name, default_notebook_id=config.default_notebook_id)
