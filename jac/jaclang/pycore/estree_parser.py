"""TypeScript/JavaScript parser using oxc-parser via Bun/Node subprocess."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import threading
from typing import TYPE_CHECKING, Any

import jaclang.pycore.unitree as uni
from jaclang.pycore.estree_transformer import EsTreeToUniAst

if TYPE_CHECKING:
    pass

_TOOLS_DIR = os.path.join(os.path.dirname(__file__), "..", "tools")
_PARSE_SCRIPT = os.path.join(_TOOLS_DIR, "ts_parse.js")
_SERVER_SCRIPT = os.path.join(_TOOLS_DIR, "ts_parse_server.js")

_runtime_cache: str | None = None
_deps_installed: bool = False


def _find_runtime() -> str:
    """Find bun or node runtime."""
    global _runtime_cache
    if _runtime_cache is not None:
        return _runtime_cache
    for cmd in ("bun", "node"):
        if shutil.which(cmd):
            _runtime_cache = cmd
            return cmd
    raise RuntimeError(
        "No JavaScript runtime found. Install bun (recommended) or node.\n"
        "  curl -fsSL https://bun.sh/install | bash"
    )


def _ensure_deps() -> None:
    """Ensure oxc-parser is installed in the tools directory."""
    global _deps_installed
    if _deps_installed:
        return
    node_modules = os.path.join(_TOOLS_DIR, "node_modules")
    if os.path.isdir(node_modules):
        _deps_installed = True
        return
    runtime = _find_runtime()
    install_cmd = [runtime, "install"] if runtime == "bun" else ["npm", "install"]
    subprocess.run(
        install_cmd,
        cwd=_TOOLS_DIR,
        capture_output=True,
        check=True,
    )
    _deps_installed = True


def parse_ts_to_estree(file_path: str, source: str | None = None) -> dict[str, Any]:
    """Parse a TypeScript/JavaScript file and return ESTree AST as dict.

    Args:
        file_path: Path to the .ts/.tsx/.js/.jsx file.
        source: Optional source string. If None, reads from file_path.

    Returns:
        Dict with keys: program, errors, comments
    """
    _ensure_deps()
    runtime = _find_runtime()

    if source is not None:
        # Pass source via stdin to avoid file I/O
        result = subprocess.run(
            [runtime, "run", _PARSE_SCRIPT, file_path, "stdin"],
            input=source,
            capture_output=True,
            text=True,
            timeout=30,
        )
    else:
        result = subprocess.run(
            [runtime, "run", _PARSE_SCRIPT, file_path],
            capture_output=True,
            text=True,
            timeout=30,
        )

    if result.returncode != 0:
        raise RuntimeError(f"oxc-parser failed for {file_path}: {result.stderr}")

    return json.loads(result.stdout)


def parse_ts_file(
    file_path: str,
    source_str: str,
    source: uni.Source,
) -> uni.Module:
    """Parse a TS/JS file and return a uni.Module.

    This is the main entry point called from compiler.py.
    """
    try:
        estree = parse_ts_to_estree(file_path, source_str)
    except Exception as e:
        # On parse failure, return a minimal module with error flag set
        mod = _make_error_module(file_path, source, str(e))
        return mod

    transformer = EsTreeToUniAst(source=source, file_path=file_path)
    mod = transformer.transform(estree)

    # Mark syntax errors if oxc-parser reported any
    if estree.get("errors"):
        mod.has_syntax_errors = True

    return mod


def _make_error_module(
    file_path: str, source: uni.Source, error_msg: str
) -> uni.Module:
    """Create an empty module with syntax error flag for parse failures."""
    mod_name = os.path.basename(file_path).split(".")[0]
    empty_tok = uni.EmptyToken(source)
    mod = uni.Module(
        name=mod_name,
        source=source,
        doc=None,
        body=[],
        terminals=[],
        kid=[empty_tok],
    )
    mod.has_syntax_errors = True
    return mod


class TsParseServer:
    """Persistent Bun subprocess for fast repeated TS parsing (LSP use)."""

    def __init__(self) -> None:
        self._proc: subprocess.Popen[str] | None = None
        self._lock = threading.Lock()
        self._request_id = 0

    def start(self) -> None:
        """Start the persistent parse server."""
        _ensure_deps()
        runtime = _find_runtime()
        self._proc = subprocess.Popen(
            [runtime, "run", _SERVER_SCRIPT],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=_TOOLS_DIR,
        )
        # Wait for ready signal
        assert self._proc.stdout is not None
        ready_line = self._proc.stdout.readline()
        try:
            ready = json.loads(ready_line)
            if not ready.get("ready"):
                raise RuntimeError(f"Parse server failed to start: {ready_line}")
        except json.JSONDecodeError as err:
            raise RuntimeError(
                f"Parse server sent invalid ready signal: {ready_line}"
            ) from err

    def parse(self, file_path: str, source: str | None = None) -> dict[str, Any]:
        """Parse a file using the persistent server."""
        if self._proc is None or self._proc.poll() is not None:
            self.start()

        with self._lock:
            self._request_id += 1
            request: dict[str, Any] = {"id": self._request_id, "file": file_path}
            if source is not None:
                request["source"] = source

            assert self._proc and self._proc.stdin and self._proc.stdout
            self._proc.stdin.write(json.dumps(request) + "\n")
            self._proc.stdin.flush()
            response_line = self._proc.stdout.readline()
            if not response_line:
                raise RuntimeError("Parse server returned empty response")
            response = json.loads(response_line)
            if "error" in response:
                raise RuntimeError(f"Parse server error: {response['error']}")
            return response

    def stop(self) -> None:
        """Stop the parse server."""
        if self._proc:
            self._proc.terminate()
            try:
                self._proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._proc.kill()
            self._proc = None

    def __del__(self) -> None:
        self.stop()
