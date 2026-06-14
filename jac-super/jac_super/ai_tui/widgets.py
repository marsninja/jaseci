"""Textual widgets for the agent TUI (ports of the old Ink components)."""

from __future__ import annotations

from rich.console import Group
from rich.text import Text
from textual.containers import VerticalScroll
from textual.suggester import SuggestFromList
from textual.widgets import Input, Static

from jac_super.ai_tui.events import (
    Feed,
    event_color,
    event_label,
    event_text,
)

COMMANDS: list[str] = [
    "/help",
    "/model",
    "/mode",
    "/context-max",
    "/verbose",
    "/feedback",
    "/stats",
    "/usage",
    "/guides",
    "/mcp",
    "/run",
    "/check",
    "/test",
    "/format",
    "/lint",
    "/cd",
    "/stop",
    "/reset",
    "/clear",
    "/exit",
]


class BannerBar(Static):
    """``jac.ai  <cwd>  <model>`` header line."""

    def set_info(self, cwd: str, model: str) -> None:
        t = Text()
        t.append("jac", style="bold magenta")
        t.append(".ai", style="bold cyan")
        t.append("  ")
        t.append(cwd or "", style="dim")
        t.append("  ")
        t.append(model or "model: unknown", style="yellow")
        self.update(t)


class StatusBar(Static):
    """Spinner + status + active phase + model + path breadcrumb."""

    def set_state(self, status: str, active: str, model: str, path: list) -> None:
        spinner = "*" if status == "running" else "o"
        color = {
            "done": "green",
            "running": "cyan",
            "stopping": "yellow",
            "error": "red",
        }.get(status, "dim")
        t = Text()
        t.append(f"{spinner} {status or 'idle'}", style=color)
        t.append("  ")
        t.append(active or "ready", style="dim")
        t.append("  ")
        t.append(model or "unknown model", style="yellow")
        if path:
            t.append("  |  ", style="dim")
            t.append(" -> ".join(str(p) for p in path), style="dim")
        self.update(t)


class StatsLine(Static):
    """Compact token/tool/health line; two lines when ``show_details``."""

    def set_stats(self, stats: dict, settings: dict, show_details: bool) -> None:
        stats = stats or {}
        settings = settings or {}
        ti = int(stats.get("tokens_in") or 0)
        to = int(stats.get("tokens_out") or 0)
        tools = int(stats.get("tools") or 0)
        errors = int(stats.get("errors") or 0)
        warnings = int(stats.get("warnings") or 0)
        line1 = f"tokens {ti}/{to} | tools {tools} | health {errors}e/{warnings}w"
        if not show_details:
            self.update(Text(line1, style="dim"))
            return
        ctx = int(settings.get("n_ctx") or 0)
        temp = float(settings.get("temperature", -1.0) or -1.0)
        elapsed = float(stats.get("elapsed") or 0.0)
        tok_s = float(stats.get("tok_per_s") or 0.0)
        ctx_text = str(ctx) if ctx > 0 else "default"
        temp_text = str(temp) if temp >= 0.0 else "default"
        line2 = f"elapsed {elapsed}s | tok/s {tok_s} | context {ctx_text} | temp {temp_text}"
        self.update(Group(Text(line1, style="dim"), Text(line2, style="dim")))


class KeyWarning(Static):
    """Hidden unless the active model needs an API key."""

    def set_key(self, needs_key: bool, key_env: str) -> None:
        self.display = bool(needs_key)
        if needs_key:
            self.update(
                Text(
                    f"Missing API key: {key_env or 'unknown'}  (ctrl+o to set)",
                    style="bold yellow",
                )
            )


class Transcript(VerticalScroll):
    """Scrollable event feed; renders the whole :class:`Feed` each update.

    Streaming events grow a single row in place, so the row count stays small
    and a full re-render per frame is cheap. Scrolls to the end on update so the
    latest output stays visible.
    """

    def compose(self):
        yield Static("No events yet.", id="transcript-body")

    def render_feed(self, feed: Feed) -> None:
        body = self.query_one("#transcript-body", Static)
        if not feed.rows:
            body.update(Text("No events yet.", style="dim"))
            return
        lines: list[Text] = []
        for row in feed.rows:
            kind = str(row.get("kind") or "")
            text = event_text(row)
            if not text:
                continue
            color = event_color(kind)
            label = event_label(kind)
            line = Text(f"{label}: {text}", style=color)
            if kind in ("tool", "tool_result"):
                line.stylize("on grey23")
            lines.append(line)
        body.update(Group(*lines) if lines else Text("No events yet.", style="dim"))
        self.scroll_end(animate=False)


class CommandInput(Input):
    """Prompt input with ``/command`` autocompletion."""

    def __init__(self, *args: object, **kwargs: object) -> None:
        kwargs.setdefault("placeholder", "Type a message or /command…")
        kwargs.setdefault("suggester", SuggestFromList(COMMANDS, case_sensitive=False))
        super().__init__(*args, **kwargs)
