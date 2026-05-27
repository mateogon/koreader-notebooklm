"""Errors for the experimental direct NotebookLM client."""

from dataclasses import dataclass


@dataclass(frozen=True)
class LiteErrorInfo:
    kind: str
    message: str
    debug: str | None = None
    status_code: int | None = None
    rpc_code: int | None = None


class NotebookLMLiteError(Exception):
    """Base direct-client error with a normalized user-facing kind."""

    def __init__(
        self,
        kind: str,
        message: str,
        *,
        debug: str | None = None,
        status_code: int | None = None,
        rpc_code: int | None = None,
    ) -> None:
        super().__init__(message)
        self.info = LiteErrorInfo(
            kind=kind,
            message=message,
            debug=debug,
            status_code=status_code,
            rpc_code=rpc_code,
        )


class AuthBundleError(NotebookLMLiteError):
    """Raised when auth bundle loading or refresh fails."""


class NotebookLMProtocolError(NotebookLMLiteError):
    """Raised when NotebookLM's private protocol cannot be parsed."""


class NotebookLMRequestError(NotebookLMLiteError):
    """Raised when a NotebookLM HTTP/RPC request fails."""
