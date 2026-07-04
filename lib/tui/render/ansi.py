"""ANSI styling helpers for the chat TUI renderer."""

from __future__ import annotations

import hashlib
import os
import sys

RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
META = "\033[38;5;244m"
BODY = "\033[38;5;252m"
INLINE_CODE = "\033[38;5;180m"
PALETTE = [39, 75, 81, 111, 117, 141, 177, 204, 207, 214, 150, 120]


def color_enabled(mode: str, *, no_color_env: bool | None = None, is_tty: bool | None = None, term: str | None = None) -> bool:
    """Return whether ANSI color should be emitted for a color mode."""
    no_color = "NO_COLOR" in os.environ if no_color_env is None else no_color_env
    if no_color:
        return False

    normalized = mode.lower()
    if normalized == "always":
        return True
    if normalized == "never":
        return False
    if normalized != "auto":
        raise ValueError(f"color mode must be auto, always, or never (got: {mode})")

    stdout_is_tty = sys.stdout.isatty() if is_tty is None else is_tty
    terminal = os.environ.get("TERM", "") if term is None else term
    return stdout_is_tty and terminal != "dumb"


def sgr(*codes: str) -> str:
    return "".join(codes)


def name_color(name: str) -> str:
    digest = hashlib.sha256(name.lower().encode()).digest()
    code = PALETTE[digest[0] % len(PALETTE)]
    return f"\033[38;5;{code}m"


def style(text: str, *codes: str, enabled: bool) -> str:
    if not enabled or not text:
        return text
    return f"{sgr(*codes)}{text}{RESET}"
