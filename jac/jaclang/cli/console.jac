"""Console utilities for terminal output.

This module provides utilities for terminal output using pure Python.
It includes:
- Basic console instance with simple print methods
- Helper functions for common output patterns
- Support for NO_COLOR and NO_EMOJI environment variables

Plugins (like jac-super) can override this to provide Rich-enhanced output.
"""
import os;
import sys;
import from contextlib { contextmanager }

"""Console utility class for terminal output in Jac CLI.

    This is the base implementation using pure Python print().
    Plugins can inherit from this and override methods to provide
    enhanced output (e.g., Rich-based formatting).
    """
class JacConsole {
    """Initialize the console."""
    def init(self: JacConsole) -> None {
        self.use_emoji = self._should_use_emoji();
        self.use_color = self._should_use_color();
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
    
    """Check if color should be used based on environment.

        Returns:
            True if color should be used, False otherwise
        """
    static def _should_use_color -> bool {
        if os.environ.get('NO_COLOR') {
            return False;
        }
        if (os.environ.get('TERM') == 'dumb') {
            return False;
        }
        return True;
    }

    """Print to stdout."""
    def print(self: JacConsole, *args: Any, **kwargs: Any) -> None {
        # Remove style and other Rich-specific kwargs
        filtered_kwargs = {k: v for (k, v) in kwargs.items() if k not in ['style', 'file']};
        print(*args, **filtered_kwargs);
    }
    
    """Context manager for status during long operations (basic implementation)."""
    def status(self: JacConsole, *args: Any, **kwargs: Any) -> object {
        # Basic implementation - just print the message
        if args {
            print(args[0] if isinstance(args[0], str) else str(args[0]));
        }
        # Return a no-op context manager
        @contextmanager
        def _noop_status() -> object {
            yield None;
        }
        return _noop_status();
    }
    
    """Print a success message with checkmark."""
    def success(self: JacConsole, message: str, emoji: bool = True) -> None {
        prefix = '✔' if (emoji and self.use_emoji) else '[SUCCESS]';
        print(f"{prefix} {message}");
    }
    
    """Print an error message with optional hint.

        Args:
            message: The error message
            hint: Optional hint or suggestion
            emoji: Whether to use emoji (✖) or text ([ERROR])
        """
    def error(
        self: JacConsole, message: str, hint: (str | None) = None, emoji: bool = True
    ) -> None {
        prefix = '✖' if (emoji and self.use_emoji) else '[ERROR]';
        print(f"{prefix} Error: {message}", file=sys.stderr);
        if hint {
            hint_prefix = '💡' if self.use_emoji else 'HINT:';
            print(f"{hint_prefix} {hint}", file=sys.stderr);
        }
    }

    """Print a warning message."""
    def warning(self: JacConsole, message: str, emoji: bool = True) -> None {
        prefix = '⚠' if (emoji and self.use_emoji) else '[WARNING]';
        print(f"{prefix} {message}");
    }
    
    """Print an info message."""
    def info(self: JacConsole, message: str, emoji: bool = True) -> None {
        prefix = 'ℹ' if (emoji and self.use_emoji) else '[INFO]';
        print(f"{prefix} {message}");
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
            print(f"{title} v{version}");
        } else {
            print(title);
        }
    }

    """Print a list of labeled URLs.

        Args:
            urls: Dict or list of tuples mapping labels to URLs
                  (e.g., {"Local": "http://localhost:3000"} or [("Local", "http://..."), ("Network", "http://...")])
            symbol: Symbol to use before each line (default: ➜)
        """
    def print_urls(self: JacConsole, urls: Any, symbol: str = '➜') -> None {
        items = urls.items() if isinstance(urls, <>dict) else urls;
        for (label, url) in items {
            padded_label = f"{label}:".ljust(10);
            print(f"  {symbol}  {padded_label} {url}");
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
        print(f"\n{title}:");
        for (i, step) in enumerate(steps, 1) {
            print(f"  {i}. {step}");
        }
        print();
    }

    """Print a list of items with symbols.

        Args:
            items: List of items to print
            style: Style name (ignored in base implementation, used by Rich plugins)
            symbol: Symbol to prefix each item
        """
    def print_list(
        self: JacConsole, items: list[str], style: str = 'success', symbol: str = '✔'
    ) -> None {
        for item in items {
            print(f"  {symbol} {item}");
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
        if title {
            print(f"\n{title}:");
        }
        # Calculate column widths
        col_widths: list[int] = [len(h) for h in headers];
        for row in rows {
            for (i, cell) in enumerate(row) {
                if i < len(col_widths) {
                    col_widths[i] = max(col_widths[i], len(str(cell)));
                }
            }
        }
        # Print header
        header_row = ' | '.join(h.ljust(w) for (h, w) in zip(headers, col_widths));
        print(header_row);
        print('-' * len(header_row));
        # Print rows
        for row in rows {
            row_str = ' | '.join(
                str(cell).ljust(w) if i < len(col_widths) else str(cell)
                for (i, cell) in enumerate(row)
                for w in [col_widths[i] if i < len(col_widths) else len(str(cell))]
            );
            print(row_str);
        }
        print();
    }

    """Context manager for spinner during long operations.

        Usage:
            with console.spinner("Loading..."):
                # do work
                pass
        """
    @contextmanager
    def spinner(self: JacConsole, text: str) -> object {
        # Basic implementation - just print the message
        print(f"{text}...", end='', flush=True);
        try {
            yield None;
        } finally {
            print(" done");
        }
    }

    """Print elapsed time in a nice format.

        Args:
            seconds: Time in seconds
        """
    def print_elapsed_time(self: JacConsole, seconds: float) -> None {
        if (seconds < 1) {
            ms = seconds * 1000;
            print(f"  Done in {ms:.0f}ms");
        } else {
            print(f"  Done in {seconds:.1f}s");
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
        emoji = emoji_map.get(action, '📝') if self.use_emoji else action.upper();
        print(f"[{timestamp}] {emoji} {action.capitalize()}: {filepath}");
    }

    """Print file watching status.

        Args:
            pattern: File pattern being watched
            count: Number of files
        """
    def print_watching(self: JacConsole, pattern: str, count: int) -> None {
        watch_emoji = '👀' if self.use_emoji else '[WATCHING]';
        print(f"{watch_emoji} Watching for changes...");
        print(f"   Monitoring: {pattern} ({count} files)");
    }
}

# Lazy initialization to avoid circular imports
glob _console_instance: (JacConsole | None) = None;

"""Get the console instance using the hook system, allowing plugins to override."""
def _get_console() -> JacConsole {
    global _console_instance;
    if _console_instance is None {
        import from jaclang.pycore.runtime { JacRuntime as Jac }
        _console_instance = Jac.get_console();
        _console_instance.init();
    }
    return _console_instance;
}

# Basic proxy class that lazily initializes the console on first access
# This allows plugins to override via the hook system while avoiding circular imports
class _ConsoleProxy {
    def __getattr__(self: _ConsoleProxy, name: str) -> Any {
        return getattr(_get_console(), name);
    }
}

# Export the proxy as console - provides clean attribute access with lazy initialization
glob console = _ConsoleProxy();
