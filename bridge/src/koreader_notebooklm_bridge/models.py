"""Request and response models for the bridge API."""

from pydantic import BaseModel, ConfigDict, Field


class HealthResponse(BaseModel):
    ok: bool = True
    service: str = "koreader-notebooklm-bridge"
    adapter: str = "mock"
    default_notebook_id: str | None = None


class BookContext(BaseModel):
    title: str | None = None
    author: str | None = None
    path: str | None = None
    position: str | None = None


class NotebookSummary(BaseModel):
    id: str
    title: str
    source_count: int = 0


class NotebookListResponse(BaseModel):
    ok: bool = True
    notebooks: list[NotebookSummary]


class NotebookCreateRequest(BaseModel):
    title: str = "KOReader Notebook"


class NotebookCreateResponse(BaseModel):
    ok: bool = True
    notebook: NotebookSummary
    url: str | None = None
    adapter: str = "mock"


class AskRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    notebook_id: str | None = None
    selected_text: str = Field(min_length=1)
    prompt: str = Field(min_length=1)
    book: BookContext | None = None


class AskResponse(BaseModel):
    ok: bool = True
    answer: str
    notebook_id: str | None = None
    adapter: str = "mock"
    conversation_id: str | None = None
    sources_used: list[str] = Field(default_factory=list)
    citations: dict[str, object] = Field(default_factory=dict)
    references: list[dict[str, object]] = Field(default_factory=list)


class BookLinkRequest(BaseModel):
    book_id: str = Field(min_length=1)
    notebook_id: str = Field(min_length=1)
    notebook_title: str | None = None
    title: str | None = None
    author: str | None = None
    path: str | None = None
    source_id: str | None = None
    linked_at: str | None = None


class BookLinkResponse(BaseModel):
    ok: bool = True
    book: BookLinkRequest


class SourceUploadRequest(BaseModel):
    notebook_id: str = Field(min_length=1)
    file_path: str = Field(min_length=1)
    title: str | None = None
    wait: bool = True


class SourceUploadResponse(BaseModel):
    ok: bool = True
    source_id: str
    title: str
    notebook_id: str
    adapter: str = "mock"
