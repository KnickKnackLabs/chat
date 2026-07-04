"""Inline body styling for mentions and code spans."""

from __future__ import annotations

import re

from .ansi import BODY, BOLD, INLINE_CODE, RESET, name_color

MENTION_RE = re.compile(r"(?<![\w/])@([A-Za-z0-9][A-Za-z0-9_.-]*)")
INLINE_CODE_RE = re.compile(r"`[^`]*`[.,;:!?)]*")


def colorize_mentions(text: str, *, enabled: bool, base_code: str = "") -> str:
    if not enabled:
        return text

    def replace(match: re.Match[str]) -> str:
        mention = match.group(0)
        name = match.group(1)
        return f"{RESET}{BOLD}{name_color(name)}{mention}{RESET}{base_code}"

    return MENTION_RE.sub(replace, text)


def render_inline_code(token: str, *, base_code: str) -> str:
    close_tick = token.rfind("`")
    code = token[1:close_tick]
    suffix = token[close_tick + 1 :]
    return f"{RESET}{BOLD}{INLINE_CODE}{code}{RESET}{base_code}{suffix}"


def colorize_body_segments(text: str, *, enabled: bool, base_code: str = BODY) -> str:
    if not enabled:
        return text

    parts: list[str] = []
    cursor = 0
    for match in INLINE_CODE_RE.finditer(text):
        if match.start() > cursor:
            parts.append(
                colorize_mentions(text[cursor : match.start()], enabled=enabled, base_code=base_code)
            )
        parts.append(render_inline_code(match.group(0), base_code=base_code))
        cursor = match.end()
    if cursor < len(text):
        parts.append(colorize_mentions(text[cursor:], enabled=enabled, base_code=base_code))
    return "".join(parts)
