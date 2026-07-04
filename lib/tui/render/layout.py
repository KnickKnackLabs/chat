"""Message block layout for the chat TUI renderer."""

from __future__ import annotations

from .ansi import BODY, BOLD, DIM, META, style, name_color
from .inline import colorize_body_segments
from .options import RenderOptions
from .wrapping import render_body

SEPARATOR_CHAR = "━"


def style_body_line(line: str, *, color: bool) -> str:
    if not color or not line:
        return line
    return f"{BODY}{colorize_body_segments(line, enabled=color, base_code=BODY)}\033[0m"


def style_separator(width: int, *, color: bool) -> str:
    return style(SEPARATOR_CHAR * width, DIM, META, enabled=color)


def plain_meta_line(timestamp: str, sender: str, message_id: str) -> str:
    line = f"{timestamp}  {sender}"
    if message_id:
        line = f"{line}  {message_id}"
    return line


def style_meta_line(timestamp: str, sender: str, message_id: str, *, color: bool) -> str:
    if not color:
        return plain_meta_line(timestamp, sender, message_id)

    parts = [
        style(timestamp, DIM, META, enabled=color),
        "  ",
        style(sender, BOLD, name_color(sender), enabled=color),
    ]
    if message_id:
        parts.extend(["  ", style(message_id, DIM, META, enabled=color)])
    return "".join(parts)


def pad_nonblank_lines(lines: list[str], message_padding: int) -> list[str]:
    if message_padding == 0:
        return lines

    prefix = " " * message_padding
    return [f"{prefix}{line}" if line else line for line in lines]


def render_message(message: dict[str, object], *, options: RenderOptions, color: bool) -> list[str]:
    sender = str(message.get("sender") or "?")
    timestamp = str(message.get("timestamp") or "")
    message_id = str(message.get("id") or "")
    body = str(message.get("body") or "")

    content_width = max(1, options.width - options.message_padding)
    body_lines = [
        style_body_line(line, color=color)
        for line in render_body(
            body,
            width=content_width,
            justify=options.justify,
            justify_style=options.justify_style,
        )
    ]
    meta_line = style_meta_line(timestamp, sender, message_id, color=color)
    separator = style_separator(content_width, color=color)

    if options.header_separator:
        lines = [
            meta_line,
            separator,
            *body_lines,
            "",
            "",
        ]
    else:
        lines = [
            separator,
            meta_line,
            *body_lines,
            "",
        ]

    return pad_nonblank_lines(lines, options.message_padding)


def render_messages(
    messages: list[dict[str, object]], *, options: RenderOptions, color: bool
) -> list[str]:
    lines: list[str] = []
    for message in messages:
        lines.extend(render_message(message, options=options, color=color))
    return lines
