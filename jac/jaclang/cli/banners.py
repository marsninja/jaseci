"""Branding and banner utilities for Jac CLI.

This module contains ASCII art, banners, and branded output for the Jac CLI.
"""

import platform
import sys

from jaclang.cli.console import console

# Jac ASCII logo
JAC_LOGO = r"""   _
  (_) __ _  ___
  | |/ _` |/ __|
  | | (_| | (__
 _/ |\__,_|\___|
|__/"""


def print_version_banner(version: str) -> None:
    """Print the full version banner with logo and system info.

    Args:
        version: Jac version string
    """
    # Get system info
    python_version = f"Python {sys.version.split()[0]}"
    platform_info = platform.platform()

    # Simplify platform string
    if platform.system() == "Linux":
        platform_short = f"Linux {platform.machine()}"
    elif platform.system() == "Darwin":
        platform_short = f"macOS {platform.machine()}"
    elif platform.system() == "Windows":
        platform_short = f"Windows {platform.machine()}"
    else:
        platform_short = platform_info

    # Print logo with info on the right
    logo_lines = JAC_LOGO.split("\n")

    console.print(logo_lines[0], style="bold cyan")
    console.print(logo_lines[1] + "     Jac Language", style="bold cyan")
    console.print(logo_lines[2], style="bold cyan")
    console.print(logo_lines[3] + f"     Version:  {version}", style="cyan")
    console.print(logo_lines[4] + f"    {python_version}", style="cyan")
    console.print(
        logo_lines[5] + f"                Platform: {platform_short}", style="cyan"
    )

    # Print helpful links
    console.print("\n📚 Documentation: [url]https://docs.jaseci.org[/url]")
    console.print("💬 Community:     [url]https://discord.gg/jaseci[/url]")
    console.print(
        "🐛 Issues:        [url]https://github.com/Jaseci-Labs/jaseci/issues[/url]"
    )
    console.print()


def print_startup_header(mode: str = "development") -> None:
    """Print header for server startup.

    Args:
        mode: Server mode (development, production, etc.)
    """
    console.print("\n  JAC DEV SERVER", style="bold cyan")
    console.print()


def print_celebration(message: str = "Happy coding!") -> None:
    """Print a celebration message.

    Args:
        message: Message to display
    """
    console.print(f"\n🚀 {message}\n", style="bold green")
