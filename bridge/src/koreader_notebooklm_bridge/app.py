"""FastAPI app for the local KOReader NotebookLM bridge.

The real NotebookLM mode delegates to the user's local `nlm` CLI. The bridge
does not copy auth files or implement MCP.
"""

from fastapi import FastAPI

from .adapters.factory import create_adapter
from .config import BridgeConfig, load_config
from .routes.ask import router as ask_router
from .routes.books import router as books_router
from .routes.health import router as health_router
from .routes.notebooks import router as notebooks_router
from .routes.sources import router as sources_router
from .services.ask_jobs import AskJobStore
from .store import BookMappingStore


def create_app(config: BridgeConfig | None = None) -> FastAPI:
    bridge_config = config or load_config()
    app = FastAPI(
        title="KOReader NotebookLM Bridge",
        version="0.1.0",
        description="Local bridge for KOReader selected-text questions.",
    )
    app.state.config = bridge_config
    app.state.adapter = create_adapter(bridge_config)
    app.state.book_store = BookMappingStore(bridge_config.data_dir)
    app.state.ask_jobs = AskJobStore()
    app.include_router(health_router)
    app.include_router(notebooks_router)
    app.include_router(books_router)
    app.include_router(sources_router)
    app.include_router(ask_router)
    return app


app = create_app()
