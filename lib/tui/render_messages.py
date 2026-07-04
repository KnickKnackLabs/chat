#!/usr/bin/env -S uv run --script
"""Render chat TUI messages with optional prose justification and color."""
# /// script
# requires-python = ">=3.10"
# ///

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from typing import Iterable

SEPARATOR = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
CODE_SPAN_OR_WORD = re.compile(r"`[^`]*`[.,;:!?)]*|\S+")
MENTION_RE = re.compile(r"(?<![\w/])@([A-Za-z0-9][A-Za-z0-9_.-]*)")

RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
META = "\033[38;5;244m"
BODY = "\033[38;5;252m"
PALETTE = [39, 75, 81, 111, 117, 141, 177, 204, 207, 214, 150, 120]


def env_positive_int(name: str, default: int) -> int:
    value = os.environ.get(name, str(default))
    if not value.isdigit() or int(value) == 0:
        print(f"Error: {name} must be a positive integer (got: {value})", file=sys.stderr)
        raise SystemExit(1)
    return int(value)


def env_bool(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def color_enabled() -> bool:
    if "NO_COLOR" in os.environ:
        return False

    mode = os.environ.get("CHAT_TUI_COLOR", "auto").lower()
    if mode == "always":
        return True
    if mode == "never":
        return False
    if mode != "auto":
        print(
            f"Error: CHAT_TUI_COLOR must be auto, always, or never (got: {mode})",
            file=sys.stderr,
        )
        raise SystemExit(1)

    return sys.stdout.isatty() and os.environ.get("TERM", "") != "dumb"


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


def colorize_mentions(text: str, enabled: bool, base_code: str = "") -> str:
    if not enabled:
        return text

    def replace(match: re.Match[str]) -> str:
        mention = match.group(0)
        name = match.group(1)
        return f"{RESET}{BOLD}{name_color(name)}{mention}{RESET}{base_code}"

    return MENTION_RE.sub(replace, text)


def style_body_line(line: str, enabled: bool) -> str:
    if not enabled or not line:
        return line
    return f"{BODY}{colorize_mentions(line, enabled, BODY)}{RESET}"


def style_separator(enabled: bool) -> str:
    return style(SEPARATOR, DIM, META, enabled=enabled)


def style_header(timestamp: str, sender: str, message_id: str, enabled: bool) -> str:
    if not enabled:
        header = f"{timestamp}  {sender}"
        if message_id:
            header = f"{header}  {message_id}"
        return header

    parts = [
        style(timestamp, DIM, META, enabled=enabled),
        "  ",
        style(sender, BOLD, name_color(sender), enabled=enabled),
    ]
    if message_id:
        parts.extend(["  ", style(message_id, DIM, META, enabled=enabled)])
    return "".join(parts)


def is_markdownish(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return False
    if line.startswith((" ", "\t")):
        return True
    if stripped.startswith(("```", "~~~", ">", "#", "- ", "* ", "+ ")):
        return True
    if re.match(r"^\d+[.)]\s", stripped):
        return True
    if "|" in stripped:
        return True
    if re.search(r"https?://\S+", stripped):
        return True
    return False


def tokenize(text: str) -> list[str]:
    return CODE_SPAN_OR_WORD.findall(text)


def wrap_tokens(tokens: Iterable[str], width: int) -> list[list[str]]:
    lines: list[list[str]] = []
    current: list[str] = []
    current_len = 0

    for token in tokens:
        token_len = len(token)
        candidate_len = token_len if not current else current_len + 1 + token_len
        if current and candidate_len > width:
            lines.append(current)
            current = [token]
            current_len = token_len
        else:
            current.append(token)
            current_len = candidate_len

    if current:
        lines.append(current)
    return lines


def justify_tokens(tokens: list[str], width: int) -> str:
    if len(tokens) <= 1:
        return " ".join(tokens)

    base_len = sum(len(token) for token in tokens)
    gaps = len(tokens) - 1
    extra = width - base_len - gaps
    if extra <= 0:
        return " ".join(tokens)

    even_extra = extra // gaps
    remainder = extra % gaps
    parts: list[str] = []
    for index, token in enumerate(tokens[:-1]):
        parts.append(token)
        spaces = 1 + even_extra + (1 if index < remainder else 0)
        parts.append(" " * spaces)
    parts.append(tokens[-1])
    return "".join(parts)


def render_prose(paragraph: str, width: int, justify: bool) -> list[str]:
    wrapped = wrap_tokens(tokenize(paragraph), width)
    if not wrapped:
        return []

    lines: list[str] = []
    last_index = len(wrapped) - 1
    for index, tokens in enumerate(wrapped):
        if justify and index != last_index:
            lines.append(justify_tokens(tokens, width))
        else:
            lines.append(" ".join(tokens))
    return lines


def render_body(body: str, width: int, justify: bool) -> list[str]:
    output: list[str] = []
    paragraph: list[str] = []

    def flush_paragraph() -> None:
        if not paragraph:
            return
        output.extend(render_prose(" ".join(paragraph), width, justify))
        paragraph.clear()

    for raw_line in body.splitlines():
        if raw_line.strip() == "":
            flush_paragraph()
            output.append("")
            continue

        if is_markdownish(raw_line):
            flush_paragraph()
            output.append(raw_line.rstrip())
            continue

        paragraph.append(raw_line.strip())

    flush_paragraph()
    return output


def render_message(
    message: dict[str, object], width: int, justify: bool, use_color: bool
) -> list[str]:
    sender = str(message.get("sender") or "?")
    timestamp = str(message.get("timestamp") or "")
    message_id = str(message.get("id") or "")
    body = str(message.get("body") or "")

    return [
        style_separator(use_color),
        style_header(timestamp, sender, message_id, use_color),
        *(style_body_line(line, use_color) for line in render_body(body, width, justify)),
        "",
    ]


def main() -> int:
    width = env_positive_int("CHAT_TUI_WRAP_WIDTH", 88)
    justify = env_bool("CHAT_TUI_JUSTIFY", False)
    use_color = color_enabled()

    try:
        messages = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"Error: failed to parse chat JSON: {exc}", file=sys.stderr)
        return 1

    for message in messages:
        for line in render_message(message, width, justify, use_color):
            print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
