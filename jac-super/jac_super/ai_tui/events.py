"""Pure event-formatting + feed model, ported from the old ``runtime.cl.jac``.

The agent bus emits structured event dicts (``kind`` + ``text`` + extras) and
re-publishes streaming ``reasoning``/``answer`` events in place under the same
``id``. :class:`Feed` mirrors the Ink client's ``processPollEvents`` logic:
it upserts events by id, assigns sequential ``#1``/``#2`` labels to tool calls,
and produces flat display rows. Kept free of any Textual import so it is unit
testable on its own.
"""

from __future__ import annotations


def event_color(kind: str) -> str:
    """Rich color for a display row, matching the old Ink palette."""
    if kind == "answer":
        return "green"
    if kind in ("tool", "tool_result"):
        return "yellow"
    if kind == "reasoning":
        return "blue"
    if kind == "error":
        return "red"
    if kind == "user":
        return "cyan"
    return "grey58"


def event_label(kind: str) -> str:
    if kind == "tool_result":
        return "result"
    return kind or "info"


def format_call_text(ev: dict) -> str:
    node_name = str(ev.get("node") or "phase")
    tokens_in = int(ev.get("tokens_in") or 0)
    tokens_out = int(ev.get("tokens_out") or 0)
    return f"{node_name} in/out={tokens_in}/{tokens_out}"


def event_text(ev: dict) -> str:
    kind = str(ev.get("kind") or "")
    text = str(ev.get("text") or "")
    if text:
        return text
    if kind == "call":
        return format_call_text(ev)
    if kind == "phase":
        return str(ev.get("node") or "phase")
    return ""


class Feed:
    """Stateful view model: raw bus events -> ordered display rows.

    A display row is ``{"id", "kind", "text"}`` where ``kind`` already maps to a
    color via :func:`event_color` and ``text`` carries any tool/result/phase
    label prefix. Streaming events grow in place (same id, longer text).
    """

    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.since_id: int = 0
        self._tool_seq: int = 1
        self._tool_label: dict[int, str] = {}
        self._result_label: dict[int, str] = {}
        self._active_tool_label: str = ""
        self.rows: list[dict] = []
        self._by_id: dict[int, dict] = {}

    def _tool_label_for(self, eid: int) -> str:
        if eid in self._tool_label:
            return self._tool_label[eid]
        lab = f"#{self._tool_seq}"
        self._tool_seq += 1
        self._tool_label[eid] = lab
        return lab

    def _row(self, ev: dict, eid: int, creating: bool) -> dict | None:
        """Port of ``eventToDisplayRow``: returns a row dict or ``None`` to skip."""
        kind = str(ev.get("kind") or "")
        text = str(ev.get("text") or "")
        if kind == "status":
            return None
        row = {"id": eid, "kind": kind, "text": text}
        if kind == "call":
            model_name = str(ev.get("model") or "")
            msg = "Call > " + format_call_text(ev)
            if model_name:
                msg += "  model=" + model_name
            row["kind"] = "system"
            row["text"] = msg
        elif kind == "phase":
            node = str(ev.get("node") or "")
            if not node:
                return None
            row["kind"] = "system"
            row["text"] = "Phase > " + node
        elif kind == "tool":
            tlab = self._tool_label_for(eid)
            self._active_tool_label = tlab
            row["text"] = "Tool " + tlab + " > " + text
        elif kind == "tool_result":
            rlab = self._result_label.get(eid, "")
            if not rlab:
                rlab = self._active_tool_label or f"#{max(1, self._tool_seq - 1)}"
                self._result_label[eid] = rlab
            row["text"] = "Result " + rlab + " > " + text
        elif kind == "answer" and not text and creating or not text and creating:
            return None
        return row

    def ingest(self, raw_events: list) -> None:
        """Upsert a batch of raw bus events into the display rows."""
        for ev in raw_events:
            eid = int(ev.get("id") or 0)
            if eid <= 0:
                continue
            if eid > self.since_id:
                self.since_id = eid
            if eid in self._by_id:
                fresh = self._row(ev, eid, False)
                if fresh is not None and fresh["text"]:
                    self._by_id[eid]["text"] = fresh["text"]
                    self._by_id[eid]["kind"] = fresh["kind"]
                continue
            row = self._row(ev, eid, True)
            if row is None:
                continue
            self._by_id[eid] = row
            self.rows.append(row)

    def apply_full(self, events: list) -> None:
        """Replace the feed from a full snapshot (mount / reset)."""
        self.reset()
        self.ingest(list(events or []))


def parse_command(line: str) -> tuple[str, str]:
    """Split a ``/cmd arg`` line into ``(cmd, arg)``; ``("", "")`` if not a command."""
    text = (line or "").strip()
    if not text.startswith("/"):
        return ("", "")
    if " " not in text:
        return (text, "")
    i = text.find(" ")
    return (text[:i], text[i + 1 :].strip())
