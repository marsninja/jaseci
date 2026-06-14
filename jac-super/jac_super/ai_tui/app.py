"""The Textual application for ``jac ai --tui`` (in-process renderer)."""

from __future__ import annotations

import contextlib
import os

from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.widgets import Static
from textual.worker import get_current_worker

from jac_super.ai_tui.bridge import AgentBridge, action_result_message
from jac_super.ai_tui.events import Feed, parse_command
from jac_super.ai_tui.messages import FrameReceived, StreamEnded, StreamError
from jac_super.ai_tui.screens import (
    HelpScreen,
    InfoScreen,
    SettingsScreen,
    UsageScreen,
)
from jac_super.ai_tui.widgets import (
    BannerBar,
    CommandInput,
    KeyWarning,
    StatsLine,
    StatusBar,
    Transcript,
)


class JacAiTuiApp(App):
    """Drives the agent in-process: one stream worker, the rest is rendering."""

    CSS = """
    BannerBar { height: auto; padding: 0 1; }
    StatusBar { height: auto; padding: 0 1; }
    StatsLine { height: auto; padding: 0 1; color: $text-muted; }
    .section { height: auto; padding: 0 1; text-style: bold; color: $accent; }
    Transcript { height: 1fr; border: round $panel; padding: 0 1; }
    KeyWarning { height: auto; padding: 0 1; }
    CommandInput { dock: bottom; border: round $accent; }
    """

    BINDINGS = [
        Binding("ctrl+c", "quit", "Quit", priority=True),
        Binding("ctrl+q", "quit", "Quit"),
        Binding("ctrl+r", "reset", "Reset"),
        Binding("ctrl+g", "stop", "Stop turn"),
        Binding("f1", "help", "Help"),
        Binding("ctrl+o", "settings", "Settings"),
    ]

    def __init__(
        self, initial_prompt: str = "", cwd: str = "", bridge: AgentBridge | None = None
    ) -> None:
        super().__init__()
        self.bridge = bridge if bridge is not None else AgentBridge()
        self.initial_prompt = (initial_prompt or "").strip()
        self.cwd = cwd or os.getcwd()
        self.feed = Feed()
        self._settings: dict = {}
        self._stats: dict = {"has_run": False}
        self._status = "idle"
        self._active = ""
        self._model = ""
        self._path: list = []
        self._show_stats_detail = False
        self._needs_key_handled = False

    # --- layout ------------------------------------------------------------
    def compose(self) -> ComposeResult:
        yield BannerBar()
        yield StatusBar()
        yield StatsLine()
        yield Static("Transcript", classes="section")
        yield Transcript()
        yield KeyWarning()
        yield CommandInput()

    def on_mount(self) -> None:
        self.banner = self.query_one(BannerBar)
        self.status_bar = self.query_one(StatusBar)
        self.stats_line = self.query_one(StatsLine)
        self.transcript = self.query_one(Transcript)
        self.key_warning = self.query_one(KeyWarning)
        self.cmd_input = self.query_one(CommandInput)

        self.banner.set_info(self.cwd, self._model)
        self.status_bar.set_state(self._status, self._active, self._model, self._path)
        self.stats_line.set_stats(self._stats, self._settings, self._show_stats_detail)
        self.key_warning.set_key(False, "")
        self.cmd_input.focus()

        self._refresh_settings()
        self._consume_stream()
        if self.initial_prompt:
            self.bridge.send(self.initial_prompt)

    def on_unmount(self) -> None:
        with contextlib.suppress(Exception):
            self.workers.cancel_group(self, "stream")
        with contextlib.suppress(Exception):
            self.bridge.stop()

    # --- streaming ---------------------------------------------------------
    @work(thread=True, exclusive=True, group="stream")
    def _consume_stream(self) -> None:
        worker = get_current_worker()
        try:
            for frame in self.bridge.stream():
                if worker.is_cancelled:
                    return
                if isinstance(frame, dict) and frame.get("heartbeat"):
                    continue
                self.post_message(FrameReceived(frame))
        except Exception as e:  # noqa: BLE001 - surface as a toast, keep app alive
            if not worker.is_cancelled:
                self.post_message(StreamError(str(e)))
            return
        if not worker.is_cancelled:
            self.post_message(StreamEnded())

    def on_frame_received(self, message: FrameReceived) -> None:
        self._apply_frame(message.frame)

    def on_stream_error(self, message: StreamError) -> None:
        self.notify(f"stream error: {message.error}", severity="error")

    def on_stream_ended(self, message: StreamEnded) -> None:
        self.notify("agent stream ended", severity="warning")

    def _apply_frame(self, frame: dict) -> None:
        if not isinstance(frame, dict) or frame.get("heartbeat"):
            return
        if frame.get("full") or frame.get("events") is not None:
            self.feed.apply_full(frame.get("events") or [])
            self.transcript.render_feed(self.feed)
        elif frame.get("ev") is not None:
            self.feed.ingest([frame["ev"]])
            self.transcript.render_feed(self.feed)

        self._status = str(frame.get("status") or "idle")
        self._active = str(frame.get("active") or "")
        self._model = str(frame.get("model_name") or self._model)
        self._path = list(frame.get("path") or [])
        self._stats = frame.get("stats") or self._stats
        needs_key = bool(frame.get("needs_key"))
        key_env = str(frame.get("key_env") or "")

        self.status_bar.set_state(self._status, self._active, self._model, self._path)
        self.banner.set_info(self.cwd, self._model)
        self.stats_line.set_stats(self._stats, self._settings, self._show_stats_detail)
        self.key_warning.set_key(needs_key, key_env)

        if needs_key and not self._needs_key_handled:
            self._needs_key_handled = True
            self._open_settings()
        elif not needs_key:
            self._needs_key_handled = False

    # --- input dispatch ----------------------------------------------------
    def on_input_submitted(self, event: CommandInput.Submitted) -> None:
        text = (event.value or "").strip()
        event.input.value = ""
        if text:
            self.handle_command(text)

    def handle_command(self, text: str) -> None:
        cmd, arg = parse_command(text)

        if cmd == "/help":
            self.push_screen(HelpScreen())
            return
        if cmd == "/usage":
            self.push_screen(UsageScreen(self._stats, self._settings))
            return
        if cmd == "/mode":
            if not arg:
                cfg = self.bridge.runtime_config()
                self.push_screen(
                    InfoScreen(
                        "Mode",
                        [
                            f"mode: {cfg.get('mode', 'unknown')}",
                            f"yolo: {'on' if cfg.get('yolo_mode') else 'off'}",
                        ],
                    )
                )
            else:
                self._notify_result(self.bridge.apply_mode(arg), "mode update failed")
            return
        if cmd in ("/verbose", "/feedback", "/stats"):
            toggler = {
                "/verbose": self.bridge.toggle_verbose,
                "/feedback": self.bridge.toggle_feedback,
                "/stats": self.bridge.toggle_stats,
            }[cmd]
            result = toggler()
            if cmd == "/stats":
                self._show_stats_detail = bool(result.get("value"))
                self.stats_line.set_stats(
                    self._stats, self._settings, self._show_stats_detail
                )
            self._notify_result(result, "toggled")
            return
        if cmd == "/guides":
            guides = self.bridge.guides()
            lines = [
                (
                    f"{g['name']} — {g['description']}"
                    if g.get("description")
                    else g["name"]
                )
                for g in guides
                if g.get("name")
            ] or ["No guides found."]
            self.push_screen(InfoScreen("Guides", lines))
            return
        if cmd == "/mcp":
            status = self.bridge.mcp_status()
            self.notify(
                status.get("message", "jac-mcp status unknown"),
                severity="information" if status.get("available") else "warning",
            )
            return
        if cmd == "/clear":
            self.feed.reset()
            self.transcript.render_feed(self.feed)
            return
        if cmd == "/stop":
            self.bridge.stop()
            self.notify("Stop requested.")
            return
        if cmd == "/reset":
            self.bridge.reset()
            self.notify("Session reset.")
            return
        if cmd == "/model":
            if not arg:
                self._open_settings()
                return
            next_model = arg.strip()
            presets = list(self._settings.get("presets") or [])
            if next_model.isdigit():
                idx = int(next_model)
                if idx <= 0 or idx > len(presets):
                    self.notify("invalid preset index", severity="error")
                    return
                next_model = str(presets[idx - 1])
            self._apply_settings(
                {
                    "model": next_model,
                    "api_key": "",
                    "base_url": "",
                    "temperature": "",
                    "n_ctx": str(int(self._settings.get("n_ctx") or 0)),
                }
            )
            return
        if cmd == "/context-max":
            if not arg:
                self.notify(f"context-max: {int(self._settings.get('n_ctx') or 0)}")
                return
            if not arg.isdigit():
                self.notify("usage: /context-max <int>", severity="error")
                return
            self._apply_settings(
                {
                    "model": str(self._settings.get("model") or ""),
                    "api_key": "",
                    "base_url": "",
                    "temperature": "",
                    "n_ctx": arg,
                }
            )
            return
        if cmd == "/cd":
            if not arg:
                self.notify(f"cwd: {self.cwd}")
                return
            result = self.bridge.set_cwd(arg)
            if result.get("ok"):
                self.cwd = arg
                self.banner.set_info(self.cwd, self._model)
            self._notify_result(result, "cd failed")
            return
        if cmd in ("/run", "/check", "/test", "/format", "/lint"):
            subcmd = cmd.lstrip("/")
            self._run_jac_cmd(subcmd, arg)
            return
        if cmd in ("/exit", "/quit"):
            self.exit(0)
            return
        if cmd:
            self.notify(f"unknown command: {text}", severity="error")
            return

        # plain prompt
        if not self.bridge.send(text):
            self.notify("wait for the active turn or stop it first", severity="warning")

    # --- settings ----------------------------------------------------------
    def _open_settings(self) -> None:
        if isinstance(self.screen, SettingsScreen):
            return

        def _after(result: dict | None) -> None:
            if result:
                self._apply_settings(result)

        self.push_screen(SettingsScreen(self._settings), _after)

    @work(thread=True, exclusive=True, group="settings")
    def _apply_settings(self, values: dict) -> None:
        result = self.bridge.apply_settings(**values)
        self.call_from_thread(self._settings_applied, result)

    def _settings_applied(self, result: dict) -> None:
        if result.get("ok"):
            self.notify(f"Settings applied; using {result.get('model', '')}")
        else:
            self.notify(result.get("error", "settings update failed"), severity="error")
        self._refresh_settings()

    def _refresh_settings(self) -> None:
        try:
            self._settings = self.bridge.settings() or {}
        except Exception:
            self._settings = {}
        self.stats_line.set_stats(self._stats, self._settings, self._show_stats_detail)

    def _notify_result(self, result: dict, fallback: str) -> None:
        self.notify(
            action_result_message(result, fallback),
            severity="information" if result.get("ok", True) else "error",
        )

    # --- jac CLI passthrough -----------------------------------------------
    @work(thread=True, group="jac_cmd")
    def _run_jac_cmd(self, subcmd: str, args_str: str) -> None:
        self.call_from_thread(self.notify, f"running: jac {subcmd} {args_str}".rstrip())
        result = self.bridge.run_jac_cmd(subcmd, args_str)
        self.call_from_thread(self._show_jac_output, result)

    def _show_jac_output(self, result: dict) -> None:
        lines = (result.get("output") or "(no output)").splitlines()
        title = result.get("cmd", "jac")
        if not result.get("ok"):
            title += "  [FAILED]"
        self.push_screen(InfoScreen(title, lines))

    # --- bindings ----------------------------------------------------------
    def action_quit(self) -> None:
        self.exit(0)

    def action_reset(self) -> None:
        self.bridge.reset()
        self.notify("Session reset.")

    def action_stop(self) -> None:
        self.bridge.stop()
        self.notify("Stop requested.")

    def action_help(self) -> None:
        self.push_screen(HelpScreen())

    def action_settings(self) -> None:
        self._open_settings()


def run_app(initial_prompt: str = "") -> int:
    cwd = os.environ.get("JAC_AI_UI_PROJECT") or os.getcwd()
    app = JacAiTuiApp(initial_prompt=initial_prompt, cwd=cwd)
    app.run()
    return int(app.return_code or 0)
