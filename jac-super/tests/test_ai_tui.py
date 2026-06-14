"""Tests for the in-process Textual TUI (jac_super.ai_tui).

The pure event/feed logic is tested directly; the app is driven with Textual's
``run_test`` pilot against a fake bridge (no live agent model needed). Async
tests use ``asyncio.run`` so no pytest-asyncio plugin is required.
"""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Iterator

from jac_super.ai_tui.app import JacAiTuiApp
from jac_super.ai_tui.events import (
    Feed,
    event_color,
    event_label,
    event_text,
    parse_command,
)
from jac_super.ai_tui.messages import FrameReceived
from jac_super.ai_tui.screens import SettingsScreen


# --------------------------------------------------------------------------- #
# Pure event/feed logic
# --------------------------------------------------------------------------- #
def test_parse_command():
    assert parse_command("/mode yolo") == ("/mode", "yolo")
    assert parse_command("/help") == ("/help", "")
    assert parse_command("hello world") == ("", "")
    assert parse_command("  ") == ("", "")


def test_event_helpers():
    assert event_color("answer") == "green"
    assert event_color("tool") == "yellow"
    assert event_color("error") == "red"
    assert event_label("tool_result") == "result"
    assert event_label("") == "info"
    assert event_text(
        {"kind": "call", "node": "Build", "tokens_in": 5, "tokens_out": 7}
    ) == ("Build in/out=5/7")


def test_feed_streaming_upserts_by_id():
    """A streaming event re-published under the same id grows one row in place."""
    feed = Feed()
    feed.ingest([{"id": 1, "kind": "answer", "text": "Hel"}])
    feed.ingest([{"id": 1, "kind": "answer", "text": "Hello"}])
    feed.ingest([{"id": 1, "kind": "answer", "text": "Hello world"}])
    answers = [r for r in feed.rows if r["kind"] == "answer"]
    assert len(answers) == 1
    assert answers[0]["text"] == "Hello world"


def test_feed_tool_labels_are_sequential():
    feed = Feed()
    feed.ingest(
        [
            {"id": 1, "kind": "tool", "text": "list_dir /tmp"},
            {"id": 2, "kind": "tool_result", "text": "a\nb"},
            {"id": 3, "kind": "tool", "text": "read_file x"},
        ]
    )
    texts = [r["text"] for r in feed.rows]
    assert texts[0] == "Tool #1 > list_dir /tmp"
    assert texts[1] == "Result #1 > a\nb"
    assert texts[2] == "Tool #2 > read_file x"


def test_feed_skips_status_and_empty():
    feed = Feed()
    feed.ingest([{"id": 1, "kind": "status", "text": "running"}])
    feed.ingest([{"id": 2, "kind": "answer", "text": ""}])
    assert feed.rows == []


def test_feed_apply_full_resets():
    feed = Feed()
    feed.ingest([{"id": 1, "kind": "user", "text": "old"}])
    feed.apply_full([{"id": 5, "kind": "user", "text": "new"}])
    assert [r["text"] for r in feed.rows] == ["new"]
    assert feed.since_id == 5


# --------------------------------------------------------------------------- #
# App pilot (fake bridge)
# --------------------------------------------------------------------------- #
class FakeBridge:
    def __init__(self):
        self.calls = []

    def stream(self) -> Iterator[dict]:
        return iter(())  # the test injects frames directly

    def settings(self) -> dict[str, object]:
        return {"model": "fake/model", "presets": ["a", "b"], "n_ctx": 0}

    def send(self, text: str) -> bool:
        self.calls.append(("send", text))
        return True

    def stop(self):
        self.calls.append(("stop",))

    def reset(self):
        self.calls.append(("reset",))

    def toggle_stats(self) -> dict[str, object]:
        return {"ok": True, "message": "Turn stats on.", "value": True}

    def toggle_verbose(self) -> dict[str, object]:
        return {"ok": True, "message": "Verbose.", "value": True}

    def toggle_feedback(self) -> dict[str, object]:
        return {"ok": True, "message": "Feedback.", "value": True}

    def run_jac_cmd(self, subcmd: str, args_str: str = "") -> dict[str, object]:
        self.calls.append(("run_jac_cmd", subcmd, args_str))
        return {
            "ok": True,
            "output": f"jac {subcmd} ok",
            "returncode": 0,
            "cmd": f"jac {subcmd}",
        }

    def set_cwd(self, path: str) -> dict[str, object]:
        self.calls.append(("set_cwd", path))
        return {"ok": True, "message": f"cwd → {path}"}


def _run(coro: Awaitable[None]) -> None:
    asyncio.run(coro)


def test_app_applies_streaming_frames():
    async def scenario():
        app = JacAiTuiApp(bridge=FakeBridge())
        async with app.run_test() as pilot:
            app.post_message(
                FrameReceived({"full": True, "events": [], "status": "idle"})
            )
            await pilot.pause()
            # Same-id streaming deltas must upsert, not duplicate.
            for txt in ("Hel", "Hello", "Hello there"):
                app.post_message(
                    FrameReceived(
                        {
                            "ev": {"id": 9, "kind": "answer", "text": txt},
                            "status": "running",
                        }
                    )
                )
                await pilot.pause()
            answers = [r for r in app.feed.rows if r["kind"] == "answer"]
            assert len(answers) == 1
            assert answers[0]["text"] == "Hello there"
            assert app._status == "running"

    _run(scenario())


def test_app_opens_settings_when_key_needed():
    async def scenario():
        app = JacAiTuiApp(bridge=FakeBridge())
        async with app.run_test() as pilot:
            app.post_message(
                FrameReceived(
                    {
                        "full": True,
                        "events": [],
                        "status": "idle",
                        "needs_key": True,
                        "key_env": "ANTHROPIC_API_KEY",
                    }
                )
            )
            await pilot.pause()
            assert app.key_warning.display is True
            assert isinstance(app.screen, SettingsScreen)

    _run(scenario())


def test_stats_command_toggles_detail():
    async def scenario():
        app = JacAiTuiApp(bridge=FakeBridge())
        async with app.run_test() as pilot:
            await pilot.pause()
            assert app._show_stats_detail is False
            app.handle_command("/stats")
            await pilot.pause()
            assert app._show_stats_detail is True

    _run(scenario())


def test_plain_text_sends_prompt():
    async def scenario():
        fake = FakeBridge()
        app = JacAiTuiApp(bridge=fake)
        async with app.run_test() as pilot:
            await pilot.pause()
            app.handle_command("hello agent")
            await pilot.pause()
            assert ("send", "hello agent") in fake.calls

    _run(scenario())


def test_jac_run_command_dispatches_to_bridge():
    async def scenario():
        fake = FakeBridge()
        app = JacAiTuiApp(bridge=fake)
        async with app.run_test() as pilot:
            await pilot.pause()
            app.handle_command("/run main.jac")
            await pilot.pause(delay=0.1)
            assert any(c[0] == "run_jac_cmd" and c[1] == "run" for c in fake.calls)

    _run(scenario())


def test_jac_check_command_dispatches_to_bridge():
    async def scenario():
        fake = FakeBridge()
        app = JacAiTuiApp(bridge=fake)
        async with app.run_test() as pilot:
            await pilot.pause()
            app.handle_command("/check")
            await pilot.pause(delay=0.1)
            assert any(c[0] == "run_jac_cmd" and c[1] == "check" for c in fake.calls)

    _run(scenario())


def test_cd_command_changes_cwd():
    import tempfile

    async def scenario():
        fake = FakeBridge()
        app = JacAiTuiApp(bridge=fake)
        async with app.run_test() as pilot:
            await pilot.pause()
            with tempfile.TemporaryDirectory() as tmpdir:
                app.handle_command(f"/cd {tmpdir}")
                await pilot.pause()
                assert ("set_cwd", tmpdir) in fake.calls
                assert app.cwd == tmpdir

    _run(scenario())
