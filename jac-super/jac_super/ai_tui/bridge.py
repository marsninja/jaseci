"""Thin in-process seam over the agent backend.

Wraps the ``ui_*`` callables from ``jaclang.cli.ai_agent`` and re-homes the
config toggles that used to live in ``ai_tui_server/extras.jac`` (now called
directly on the live ``agent`` glob, so a toggle takes effect on the same
object the turn thread reads). The whole former HTTP/SSE layer was a 1:1
passthrough to these functions.
"""

from __future__ import annotations

import contextlib
from collections.abc import Iterator


class AgentBridge:
    """Stateless wrapper; all state lives on the shared ``agent`` glob.

    The ``jaclang.cli.ai_agent`` import is deferred to construction (it builds
    the default model at import), so importing this module -- and the Textual
    app -- stays cheap and unit-testable with a fake bridge.
    """

    def __init__(self) -> None:
        import jaclang.cli.ai_agent as _agent_mod

        self._m = _agent_mod
        self._agent = _agent_mod.agent

    # --- lifecycle ---------------------------------------------------------
    def configure(self) -> None:
        self._m.ui_configure()

    # --- streaming + turn control -----------------------------------------
    def stream(self) -> Iterator[dict]:
        return self._m.ui_stream()

    def send(self, text: str) -> bool:
        """Start a turn; ``False`` if one is already running."""
        return bool(self._m.ui_send(text))

    def stop(self) -> None:
        self._m.ui_stop()

    def reset(self) -> None:
        self._m.ui_reset()

    def poll(self) -> dict:
        return self._m.ui_poll()

    # --- settings ----------------------------------------------------------
    def settings(self) -> dict:
        return self._m.ui_settings()

    def apply_settings(
        self,
        model: str = "",
        api_key: str = "",
        base_url: str = "",
        temperature: str = "",
        n_ctx: str = "",
    ) -> dict:
        return self._m.ui_apply_settings(model, api_key, base_url, temperature, n_ctx)

    def call_detail(self, call_id: int) -> dict:
        return self._m.ui_call_detail(call_id)

    def phase_context(self, phase: str) -> dict:
        return self._m.ui_phase_context(phase)

    def graph(self) -> dict:
        return self._m.ui_graph()

    # --- runtime toggles (ex-extras.jac) ----------------------------------
    def runtime_config(self) -> dict:
        cfg = self._agent.cfg
        return {
            "yolo_mode": cfg.yolo_mode,
            "verbose": cfg.verbose,
            "inline_feedback": cfg.inline_feedback,
            "show_stats": cfg.show_stats,
            "mode": "yolo" if cfg.yolo_mode else "safe",
        }

    def apply_mode(self, mode: str) -> dict:
        m = (mode or "").strip().lower()
        if m == "yolo":
            self._agent.cfg.yolo_mode = True
            return {"ok": True, "message": "YOLO mode: writes run without confirm."}
        if m == "safe":
            self._agent.cfg.yolo_mode = False
            return {
                "ok": True,
                "message": "Safe mode: confirms writes and shell commands.",
            }
        return {"ok": False, "error": "usage: /mode safe|yolo"}

    def toggle_verbose(self) -> dict:
        cfg = self._agent.cfg
        cfg.verbose = not cfg.verbose
        msg = (
            "Verbose: streaming reasoning, timings, and step detail."
            if cfg.verbose
            else "Quiet: tool calls and the answer only."
        )
        return {"ok": True, "message": msg, "value": cfg.verbose}

    def toggle_feedback(self) -> dict:
        cfg = self._agent.cfg
        cfg.inline_feedback = not cfg.inline_feedback
        msg = (
            "Inline compiler feedback on: writes report errors they introduce."
            if cfg.inline_feedback
            else "Inline compiler feedback off: use jac_check to compile."
        )
        return {"ok": True, "message": msg, "value": cfg.inline_feedback}

    def toggle_stats(self) -> dict:
        cfg = self._agent.cfg
        cfg.show_stats = not cfg.show_stats
        msg = "Turn stats on." if cfg.show_stats else "Turn stats off."
        return {"ok": True, "message": msg, "value": cfg.show_stats}

    def guides(self) -> list[dict]:
        from jaclang.cli.guide_store import list_guides

        out: list[dict] = []
        for g in list_guides():
            out.append({"name": g.name, "description": g.description})
        return out

    def mcp_status(self) -> dict:
        try:
            from importlib.util import find_spec

            if find_spec("jac_mcp") is not None:
                return {
                    "available": True,
                    "message": "jac-mcp plugin is installed. Use `jac mcp` to manage servers.",
                }
        except Exception:
            pass
        return {
            "available": False,
            "message": "jac-mcp is not loaded in this session.",
        }

    def run_jac_cmd(self, subcmd: str, args_str: str = "") -> dict:
        """Run ``jac <subcmd> [args]`` in the current workspace directory."""
        import shlex
        import subprocess

        cwd = None
        with contextlib.suppress(Exception):
            cwd = self._agent.ws.cwd or None
        cmd = ["jac", subcmd] + (shlex.split(args_str) if args_str else [])
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=120,
                cwd=cwd,
            )
            combined = (result.stdout + result.stderr).strip()
            return {
                "ok": result.returncode == 0,
                "output": combined or "(no output)",
                "returncode": result.returncode,
                "cmd": " ".join(cmd),
            }
        except FileNotFoundError:
            return {
                "ok": False,
                "output": "jac not found on PATH",
                "returncode": 1,
                "cmd": " ".join(cmd),
            }
        except subprocess.TimeoutExpired:
            return {
                "ok": False,
                "output": "command timed out (120s)",
                "returncode": 1,
                "cmd": " ".join(cmd),
            }
        except Exception as e:
            return {
                "ok": False,
                "output": str(e),
                "returncode": 1,
                "cmd": " ".join(cmd),
            }

    def set_cwd(self, path: str) -> dict:
        """Change the agent workspace directory."""
        import os

        resolved = os.path.normpath(os.path.expanduser(path))
        if not os.path.isdir(resolved):
            return {"ok": False, "error": f"not a directory: {resolved}"}
        try:
            self._agent.ws.set_cwd(resolved)
            return {"ok": True, "message": f"cwd → {resolved}"}
        except Exception as e:
            return {"ok": False, "error": str(e)}


def action_result_message(result: object, fallback: str) -> str:
    """First non-empty of message/error/fallback (ports the Ink helper)."""
    if not isinstance(result, dict):
        return fallback
    return str(result.get("message") or result.get("error") or fallback)
