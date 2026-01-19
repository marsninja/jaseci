"""Console utilities for beautiful terminal output.

This module provides utilities for creating professional, colorful terminal
output using the rich library. It includes:
- Themed console instance
- Helper functions for common output patterns
- Spinner and progress utilities
- Support for NO_COLOR environment variable
"""

import os
import sys
from contextlib import contextmanager
from typing import Any, Dict, List, Optional

from rich.console import Console as RichConsole
from rich.panel import Panel
from rich.table import Table
from rich.theme import Theme


class JacConsole:
    """Console utility class for beautiful terminal output in Jac CLI.

    This class wraps Rich's Console with custom theming and convenience methods
    for common output patterns used throughout the Jac CLI.
    """

    # Custom theme for Jac CLI
    JAC_THEME = Theme(
        {
            "success": "bold green",
            "error": "bold red",
            "warning": "bold yellow",
            "info": "bold cyan",
            "url": "underline green",
            "muted": "dim white",
            "highlight": "bold cyan",
            "time": "yellow",
        }
    )

    def __init__(self) -> None:
        """Initialize the console with Jac theme."""
        # Create console instance with theme
        # Respects NO_COLOR environment variable automatically
        self._console = RichConsole(theme=self.JAC_THEME)
        self.use_emoji = self._should_use_emoji()

    @staticmethod
    def _should_use_emoji() -> bool:
        """Check if emoji should be used based on environment.

        Returns:
            True if emoji should be used, False otherwise
        """
        # Check for NO_EMOJI or TERM=dumb
        if os.environ.get("NO_EMOJI") or os.environ.get("TERM") == "dumb":
            return False

        # Windows Command Prompt has issues with emoji
        if sys.platform == "win32" and not os.environ.get("WT_SESSION"):
            return False

        return True

    def print(self, *args, **kwargs) -> None:
        """Delegate to rich console print method."""
        self._console.print(*args, **kwargs)

    def status(self, *args, **kwargs):
        """Delegate to rich console status method."""
        return self._console.status(*args, **kwargs)

    def success(self, message: str, emoji: bool = True) -> None:
        """Print a success message with checkmark."""
        prefix = "✔" if (emoji and self.use_emoji) else "[SUCCESS]"
        self._console.print(f"{prefix} {message}", style="success")

    def error(self, message: str, hint: Optional[str] = None, emoji: bool = True) -> None:
        """Print an error message with optional hint.

        Args:
            message: The error message
            hint: Optional hint or suggestion
            emoji: Whether to use emoji (✖) or text ([ERROR])
        """
        prefix = "✖" if (emoji and self.use_emoji) else "[ERROR]"
        self._console.print(f"{prefix} Error: {message}", style="error", file=sys.stderr)
        if hint:
            hint_prefix = "💡" if self.use_emoji else "HINT:"
            self._console.print(f"\n  {hint_prefix} {hint}", style="info", file=sys.stderr)

    def warning(self, message: str, emoji: bool = True) -> None:
        """Print a warning message."""
        prefix = "⚠" if (emoji and self.use_emoji) else "[WARNING]"
        self._console.print(f"{prefix} {message}", style="warning")

    def info(self, message: str, emoji: bool = True) -> None:
        """Print an info message."""
        prefix = "ℹ" if (emoji and self.use_emoji) else "[INFO]"
        self._console.print(f"{prefix} {message}", style="info")

    def print_header(self, title: str, version: Optional[str] = None) -> None:
        """Print a header with optional version.

        Args:
            title: Header title
            version: Optional version string
        """
        if version:
            self._console.print(f"\n  {title} v{version}\n", style="bold cyan")
        else:
            self._console.print(f"\n  {title}\n", style="bold cyan")

    def print_urls(self, urls, symbol: str = "➜") -> None:
        """Print a list of labeled URLs.

        Args:
            urls: Dict or list of tuples mapping labels to URLs
                  (e.g., {"Local": "http://localhost:3000"} or [("Local", "http://..."), ("Network", "http://...")])
            symbol: Symbol to use before each line (default: ➜)
        """
        # Handle both dict and list of tuples
        items = urls.items() if isinstance(urls, dict) else urls

        for label, url in items:
            # Pad label to align URLs nicely
            padded_label = f"{label}:".ljust(10)
            self._console.print(f"  {symbol}  {padded_label} [url]{url}[/url]")

    def print_next_steps(self, steps: List[str], title: str = "Next Steps") -> None:
        """Print a bordered box with next steps.

        Args:
            steps: List of step strings
            title: Box title (default: "Next Steps")
        """
        # Create numbered list
        content = "\n".join(f"  {i}  {step}" for i, step in enumerate(steps, 1))

        panel = Panel(
            content,
            title=title,
            border_style="cyan",
            padding=(0, 1),
        )
        self._console.print(panel)

    def print_list(self, items: List[str], style: str = "success", symbol: str = "✔") -> None:
        """Print a list of items with symbols.

        Args:
            items: List of items to print
            style: Rich style to apply
            symbol: Symbol to prefix each item
        """
        for item in items:
            self._console.print(f"  {symbol} {item}", style=style)

    def print_table(
        self,
        headers: List[str],
        rows: List[List[str]],
        title: Optional[str] = None,
    ) -> None:
        """Print a formatted table.

        Args:
            headers: Column headers
            rows: List of rows (each row is a list of strings)
            title: Optional table title
        """
        table = Table(title=title, show_header=True, header_style="bold cyan")

        for header in headers:
            table.add_column(header)

        for row in rows:
            table.add_row(*row)

        self._console.print(table)

    @contextmanager
    def spinner(self, text: str):
        """Context manager for spinner during long operations.

        Usage:
            with console.spinner("Loading..."):
                # do work
                pass
        """
        with self._console.status(f"[cyan]{text}[/cyan]", spinner="dots") as status:
            yield status

    def print_elapsed_time(self, seconds: float) -> None:
        """Print elapsed time in a nice format.

        Args:
            seconds: Time in seconds
        """
        if seconds < 1:
            ms = seconds * 1000
            self._console.print(f"  Done in {ms:.0f}ms", style="muted")
        else:
            self._console.print(f"  Done in {seconds:.1f}s", style="muted")

    def print_file_change(self, filepath: str, action: str = "changed") -> None:
        """Print file change notification with timestamp.

        Args:
            filepath: Path to the file
            action: Action performed (changed, created, deleted)
        """
        from datetime import datetime

        timestamp = datetime.now().strftime("%H:%M:%S")

        emoji_map = {
            "changed": "⚡",
            "created": "✨",
            "deleted": "🗑️",
        }

        emoji = emoji_map.get(action, "📝")
        self._console.print(f"[{timestamp}] {emoji} {action.capitalize()}: {filepath}", style="info")

    def print_watching(self, pattern: str, count: int) -> None:
        """Print file watching status.

        Args:
            pattern: File pattern being watched
            count: Number of files
        """
        watch_emoji = "👀" if self.use_emoji else "[WATCHING]"
        self._console.print(f"\n{watch_emoji} Watching for changes...", style="info")
        self._console.print(f"   Monitoring: {pattern} ({count} files)", style="muted")


# Create global console instance as a singleton
console = JacConsole()
