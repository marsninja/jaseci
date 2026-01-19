"""Console utilities for beautiful terminal output.

This module provides utilities for creating professional, colorful terminal
output using the rich library. It includes:
- Themed console instance
- Helper functions for common output patterns
- Spinner and progress utilities
- Support for NO_COLOR environment variable
"""
import os;
import sys;
import from contextlib { contextmanager }
import from rich.console { Console as RichConsole }
import from rich.panel { Panel }
import from rich.table { Table }
import from rich.theme { Theme }
"""Console utility class for beautiful terminal output in Jac CLI.

    This class wraps Rich's Console with custom theming and convenience methods
    for common output patterns used throughout the Jac CLI.
    """
class JacConsole {
    with entry {
        JAC_THEME = Theme(
            {
                'success': 'bold green',
                'error': 'bold red',
                'warning': 'bold yellow',
                'info': 'bold cyan',
                'url': 'underline green',
                'muted': 'dim white',
                'highlight': 'bold cyan',
                'time': 'yellow'
            }
        );
    }

    """Initialize the console with Jac theme."""
    def init(self: JacConsole) -> None {
        self._console = RichConsole(theme=self.JAC_THEME);
        self.use_emoji = self._should_use_emoji();
    }
    """Check if emoji should be used based on environment.

        Returns:
            True if emoji should be used, False otherwise
        """
    static def _should_use_emoji -> bool {
        if (os.environ.get('NO_EMOJI') or (os.environ.get('TERM') == 'dumb')) {
            return False;
        }
        if ((sys.platform == 'win32') and not os.environ.get('WT_SESSION')) {
            return False;
        }
        return True;
    }

    """Delegate to rich console print method."""
    def print(self: JacConsole, *args: Any, **kwargs: Any) -> None {
        self._console.print(*args, **kwargs);
    }
    """Delegate to rich console status method."""
    def status(self: JacConsole, *args: Any, **kwargs: Any) -> object {
        return self._console.status(*args, **kwargs);
    }
    """Print a success message with checkmark."""
    def success(self: JacConsole, message: str, emoji: bool = True) -> None {
        prefix = '✔' if (emoji and self.use_emoji) else '[SUCCESS]';
        self._console.print(f"{prefix} {message}", style='success');
    }
    """Print an error message with optional hint.

        Args:
            message: The error message
            hint: Optional hint or suggestion
            emoji: Whether to use emoji (â) or text ([ERROR])
        """
    def error(
        self: JacConsole, message: str, hint: (str | None) = None, emoji: bool = True
    ) -> None {
        prefix = '✖' if (emoji and self.use_emoji) else '[ERROR]';
        self._console.print(
            f"{prefix} Error: {message}", style='error', file=sys.stderr
        );
        if hint {
            hint_prefix = '💡' if self.use_emoji else 'HINT:';
            self._console.print(f"{hint_prefix} {hint}", style='info', file=sys.stderr);
        }
    }

    """Print a warning message."""
    def warning(self: JacConsole, message: str, emoji: bool = True) -> None {
        prefix = '⚠' if (emoji and self.use_emoji) else '[WARNING]';
        self._console.print(f"{prefix} {message}", style='warning');
    }
    """Print an info message."""
    def info(self: JacConsole, message: str, emoji: bool = True) -> None {
        prefix = 'ℹ' if (emoji and self.use_emoji) else '[INFO]';
        self._console.print(f"{prefix} {message}", style='info');
    }
    """Print a header with optional version.

        Args:
            title: Header title
            version: Optional version string
        """
    def print_header(
        self: JacConsole, title: str, version: (str | None) = None
    ) -> None {
        if version {
            self._console.print(f"{title} v{version}", style='bold cyan');
        } else {
            self._console.print(f"{title}", style='bold cyan');
        }
    }

    """Print a list of labeled URLs.

        Args:
            urls: Dict or list of tuples mapping labels to URLs
                  (e.g., {"Local": "http://localhost:3000"} or [("Local", "http://..."), ("Network", "http://...")])
            symbol: Symbol to use before each line (default: â)
        """
    def print_urls(self: JacConsole, urls: Any, symbol: str = '➜') -> None {
        items = urls.items() if isinstance(urls, <>dict) else urls;
        for (label, url) in items {
            padded_label = f"{label}:".ljust(10);
            self._console.print(f"  {symbol}  {padded_label} [url]{url}[/url]");
        }
    }

    """Print a bordered box with next steps.

        Args:
            steps: List of step strings
            title: Box title (default: "Next Steps")
        """
    def print_next_steps(
        self: JacConsole, steps: list[str], title: str = 'Next Steps'
    ) -> None {
        content = '\n'.join(f"  {i}  {step}" for (i, step) in enumerate(steps, 1));
        panel = Panel(content, title=title, border_style='cyan', padding=(0, 1));
        self._console.print(panel);
    }

    """Print a list of items with symbols.

        Args:
            items: List of items to print
            style: Rich style to apply
            symbol: Symbol to prefix each item
        """
    def print_list(
        self: JacConsole, items: list[str], style: str = 'success', symbol: str = '✔'
    ) -> None {
        for item in items {
            self._console.print(f"  {symbol} {item}", style=style);
        }
    }

    """Print a formatted table.

        Args:
            headers: Column headers
            rows: List of rows (each row is a list of strings)
            title: Optional table title
        """
    def print_table(
        self: JacConsole,
        headers: list[str],
        rows: list[list[str]],
        title: (str | None) = None
    ) -> None {
        table = Table(title=title, show_header=True, header_style='bold cyan');
        for header in headers {
            table.add_column(header);
        }
        for row in rows {
            table.add_row(*row);
        }
        self._console.print(table);
    }

    """Context manager for spinner during long operations.

        Usage:
            with console.spinner("Loading..."):
                # do work
                pass
        """
    @contextmanager
    def spinner(self: JacConsole, text: str) -> object {
        with self._console.status(f"[cyan]{text}[/cyan]", spinner='dots') as status {
            yield status;
            ;
        }
    }

    """Print elapsed time in a nice format.

        Args:
            seconds: Time in seconds
        """
    def print_elapsed_time(self: JacConsole, seconds: float) -> None {
        if (seconds < 1) {
            ms = seconds * 1000;
            self._console.print(f"  Done in {ms:f'.0f'}ms", style='muted');
        } else {
            self._console.print(f"  Done in {seconds:f'.1f'}s", style='muted');
        }
    }

    """Print file change notification with timestamp.

        Args:
            filepath: Path to the file
            action: Action performed (changed, created, deleted)
        """
    def print_file_change(
        self: JacConsole, filepath: str, action: str = 'changed'
    ) -> None {
        import from datetime { datetime }
        timestamp = datetime.now().strftime('%H:%M:%S');
        emoji_map = {'changed': '⚡', 'created': '✨', 'deleted': '🗑️'};
        emoji = emoji_map.get(action, '📝');
        self._console.print(
            f"[{timestamp}] {emoji} {action.capitalize()}: {filepath}", style='info'
        );
    }

    """Print file watching status.

        Args:
            pattern: File pattern being watched
            count: Number of files
        """
    def print_watching(self: JacConsole, pattern: str, count: int) -> None {
        watch_emoji = '👀' if self.use_emoji else '[WATCHING]';
        self._console.print(f"{watch_emoji} Watching for changes...", style='info');
        self._console.print(f"   Monitoring: {pattern} ({count} files)", style='muted');
    }
}

glob console = JacConsole();