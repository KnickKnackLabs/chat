#!/usr/bin/env -S uv run --script
"""Render chat TUI messages from JSON stdin."""
# /// script
# requires-python = ">=3.10"
# ///

from render.cli import main


if __name__ == "__main__":
    raise SystemExit(main())
