#!/usr/bin/env -S uv run --script
"""Render chat TUI messages with optional prose justification."""
# /// script
# requires-python = ">=3.10"
# ///

from __future__ import annotations

import json
import os
import re
import sys
from typing import Iterable

SEPARATOR = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
CODE_SPAN_OR_WORD = re.compile(r"`[^`]*`[.,;:!?)]*|\S+")


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


def render_message(message: dict[str, object], width: int, justify: bool) -> list[str]:
    sender = str(message.get("sender") or "?")
    timestamp = str(message.get("timestamp") or "")
    message_id = str(message.get("id") or "")
    body = str(message.get("body") or "")

    header = f"{timestamp}  {sender}"
    if message_id:
        header = f"{header}  {message_id}"

    return [SEPARATOR, header, *render_body(body, width, justify), ""]


def main() -> int:
    width = env_positive_int("CHAT_TUI_WRAP_WIDTH", 88)
    justify = env_bool("CHAT_TUI_JUSTIFY", False)

    try:
        messages = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"Error: failed to parse chat JSON: {exc}", file=sys.stderr)
        return 1

    for message in messages:
        for line in render_message(message, width, justify):
            print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
