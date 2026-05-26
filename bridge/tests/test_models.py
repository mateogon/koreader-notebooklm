"""Bridge model tests."""

import pytest
from pydantic import ValidationError

from koreader_notebooklm_bridge.models import AskRequest, BookContext


def test_ask_request_accepts_book_context():
    request = AskRequest(
        notebook_id="mock-notebook",
        selected_text="A selected passage.",
        prompt="Explain this.",
        book=BookContext(title="Test Book", position="12%"),
    )

    assert request.notebook_id == "mock-notebook"
    assert request.book is not None
    assert request.book.title == "Test Book"


def test_ask_request_requires_selected_text():
    with pytest.raises(ValidationError):
        AskRequest(selected_text="", prompt="Explain this.")
