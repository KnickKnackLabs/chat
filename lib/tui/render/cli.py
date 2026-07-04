"""CLI for rendering chat JSON into the TUI message pane."""

from __future__ import annotations

import json
import os
import sys

from .ansi import color_enabled
from .layout import render_messages
from .options import from_env


def main() -> int:
    try:
        options = from_env()
        use_color = color_enabled(
            options.color_mode,
            no_color_env="NO_COLOR" in os.environ,
            term=os.environ.get("TERM", ""),
        )
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    try:
        messages = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"Error: failed to parse chat JSON: {exc}", file=sys.stderr)
        return 1

    for line in render_messages(messages, options=options, color=use_color):
        print(line)
    return 0
