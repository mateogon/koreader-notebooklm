"""Mock adapter for local bridge development."""

from ..models import (
    AskRequest,
    AskResponse,
    NotebookCreateResponse,
    NotebookSummary,
    SourceUploadRequest,
    SourceUploadResponse,
)


class MockNotebookLMAdapter:
    name = "mock"

    def list_notebooks(self) -> list[NotebookSummary]:
        return [
            NotebookSummary(
                id="mock-notebook",
                title="Mock Notebook",
                source_count=1,
            )
        ]

    def ask(self, request: AskRequest) -> AskResponse:
        preview = request.selected_text.strip().replace("\n", " ")[:160]
        answer = (
            f"Mock NotebookLM response for prompt: {request.prompt.strip()}\n\n"
            f"Selected passage: {preview}"
        )
        return AskResponse(
            answer=answer,
            notebook_id=request.notebook_id or "mock-notebook",
            adapter=self.name,
        )

    def create_notebook(self, title: str) -> NotebookCreateResponse:
        notebook = NotebookSummary(id="mock-created-notebook", title=title, source_count=0)
        return NotebookCreateResponse(notebook=notebook, adapter=self.name)

    def upload_source(self, request: SourceUploadRequest) -> SourceUploadResponse:
        title = request.title or request.file_path.rsplit("/", 1)[-1]
        return SourceUploadResponse(
            source_id="mock-source",
            title=title,
            notebook_id=request.notebook_id,
            adapter=self.name,
        )
