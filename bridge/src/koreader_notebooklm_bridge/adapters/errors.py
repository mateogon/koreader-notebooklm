"""Adapter errors."""


class AdapterError(Exception):
    """Base adapter failure exposed as an HTTP error by routes."""


class AdapterNotConfiguredError(AdapterError):
    """Raised when adapter configuration is incomplete."""


class AdapterCommandError(AdapterError):
    """Raised when an external adapter command fails."""

