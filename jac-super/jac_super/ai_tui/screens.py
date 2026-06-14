"""Modal overlays: Help, Usage, Info, and Settings."""

from __future__ import annotations

from rich.text import Text
from textual.app import ComposeResult
from textual.containers import Grid, VerticalScroll
from textual.screen import ModalScreen
from textual.widgets import Button, Input, Label, Static

from jac_super.ai_tui.widgets import COMMANDS

_HELP_LINES = [
    "/model [name|#] to inspect or switch models",
    "/mode [safe|yolo] to inspect or change approvals",
    "/context-max [n] to inspect or update the context cap",
    "/verbose and /feedback toggle agent display flags",
    "/stats toggles per-turn stats; /usage shows the usage panel",
    "/guides lists bundled reference guides; /mcp shows MCP status",
    "/run [file] [args] — jac run (execute a .jac file)",
    "/check [file] — jac check (type-check a file or project)",
    "/test [args] — jac test (run the project test suite)",
    "/format [file] — jac format (auto-format a file)",
    "/lint [file] — jac lint (lint a file or project)",
    "/cd [path] — change the agent workspace directory",
    "/reset clears the session; /stop halts the active turn; /exit quits",
]


class _DismissScreen(ModalScreen):
    """Base for read-only overlays dismissed with Escape/Enter."""

    BINDINGS = [("escape", "dismiss", "Close"), ("enter", "dismiss", "Close")]

    DEFAULT_CSS = """
    _DismissScreen {
        align: center middle;
    }
    _DismissScreen > VerticalScroll {
        width: 70%;
        max-width: 100;
        height: auto;
        max-height: 80%;
        border: round $accent;
        background: $surface;
        padding: 1 2;
    }
    _DismissScreen .panel-title {
        text-style: bold;
        color: $accent;
    }
    """

    def action_dismiss(self) -> None:
        self.dismiss(None)


class HelpScreen(_DismissScreen):
    def compose(self) -> ComposeResult:
        with VerticalScroll():
            yield Static("Commands", classes="panel-title")
            yield Static(Text(", ".join(COMMANDS), style="dim"))
            for line in _HELP_LINES:
                yield Static(Text(line, style="dim"))


class InfoScreen(_DismissScreen):
    def __init__(self, title: str, lines: list[str]) -> None:
        super().__init__()
        self._title = title or "Info"
        self._lines = lines or []

    def compose(self) -> ComposeResult:
        with VerticalScroll():
            yield Static(self._title, classes="panel-title")
            if not self._lines:
                yield Static(Text("(nothing to show)", style="dim"))
            for line in self._lines:
                yield Static(Text(str(line), style="dim"))


class UsageScreen(_DismissScreen):
    def __init__(self, stats: dict, settings: dict) -> None:
        super().__init__()
        self._stats = stats or {}
        self._settings = settings or {}

    def compose(self) -> ComposeResult:
        s = self._stats
        st = self._settings
        with VerticalScroll():
            yield Static("Usage", classes="panel-title")
            if not s.get("has_run"):
                yield Static(Text("No completed turn yet.", style="dim"))
                return
            rows = [
                f"tokens in/out: {int(s.get('tokens_in') or 0)}/{int(s.get('tokens_out') or 0)}",
                f"throughput: {float(s.get('tok_per_s') or 0.0)} tok/s",
                f"cost: {float(s.get('cost') or 0.0)}",
                (
                    "reads/writes/runs/files: "
                    f"{int(s.get('reads') or 0)}/{int(s.get('writes') or 0)}/"
                    f"{int(s.get('runs') or 0)}/{int(s.get('files') or 0)}"
                ),
                f"ctx max: {int(st.get('n_ctx') or 0)}",
            ]
            for r in rows:
                yield Static(Text(r, style="dim"))


class SettingsScreen(ModalScreen):
    """Edit model/key/base_url/temperature/context; dismisses with a values dict.

    The app applies the result via ``bridge.apply_settings`` (which rebuilds the
    model and may block, so it runs off the event loop). A blank api_key keeps
    the currently held key.
    """

    BINDINGS = [("escape", "cancel", "Cancel")]

    DEFAULT_CSS = """
    SettingsScreen {
        align: center middle;
    }
    SettingsScreen > Grid {
        grid-size: 2;
        grid-columns: 16 1fr;
        grid-rows: auto;
        width: 70%;
        max-width: 90;
        height: auto;
        border: round $accent;
        background: $surface;
        padding: 1 2;
    }
    SettingsScreen .settings-title {
        column-span: 2;
        text-style: bold;
        color: $accent;
        margin-bottom: 1;
    }
    SettingsScreen .buttons {
        column-span: 2;
        align-horizontal: right;
        height: auto;
        margin-top: 1;
    }
    SettingsScreen Label {
        padding: 1 1 0 0;
    }
    """

    def __init__(self, settings: dict) -> None:
        super().__init__()
        self._settings = settings or {}

    def compose(self) -> ComposeResult:
        s = self._settings
        temp = float(s.get("temperature", -1.0) or -1.0)
        ctx = int(s.get("n_ctx") or 0)
        presets = ", ".join(str(p) for p in (s.get("presets") or []))
        with Grid():
            yield Static("Settings", classes="settings-title")
            yield Label("model")
            yield Input(value=str(s.get("model") or ""), id="set-model")
            yield Label("api key")
            yield Input(
                value="",
                password=True,
                placeholder=("(held)" if s.get("api_key_set") else "(none)"),
                id="set-key",
            )
            yield Label("base url")
            yield Input(value=str(s.get("base_url") or ""), id="set-base")
            yield Label("temperature")
            yield Input(value=("" if temp < 0 else str(temp)), id="set-temp")
            yield Label("context max")
            yield Input(value=("" if ctx <= 0 else str(ctx)), id="set-ctx")
            if presets:
                yield Static("", classes="settings-title")
                yield Static(Text(f"presets: {presets}", style="dim"))
            with Grid(classes="buttons"):
                yield Button("Apply", variant="primary", id="apply")
                yield Button("Cancel", id="cancel")

    def _collect(self) -> dict:
        return {
            "model": self.query_one("#set-model", Input).value.strip(),
            "api_key": self.query_one("#set-key", Input).value,
            "base_url": self.query_one("#set-base", Input).value.strip(),
            "temperature": self.query_one("#set-temp", Input).value.strip(),
            "n_ctx": self.query_one("#set-ctx", Input).value.strip(),
        }

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "apply":
            self.dismiss(self._collect())
        else:
            self.dismiss(None)

    def on_input_submitted(self, event: Input.Submitted) -> None:
        self.dismiss(self._collect())

    def action_cancel(self) -> None:
        self.dismiss(None)
