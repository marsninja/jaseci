"""Textual messages posted from the background stream worker to the app."""

from __future__ import annotations

from textual.message import Message


class FrameReceived(Message):
    """One frame from ``ui_stream`` (full snapshot, event delta, or state)."""

    def __init__(self, frame: dict) -> None:
        self.frame = frame
        super().__init__()


class StreamEnded(Message):
    """The stream generator returned (the agent process is shutting down)."""


class StreamError(Message):
    """The stream worker raised; carries the error text for a toast."""

    def __init__(self, error: str) -> None:
        self.error = error
        super().__init__()
