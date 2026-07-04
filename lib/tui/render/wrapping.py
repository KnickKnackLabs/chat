"""Paragraph wrapping and justification for chat TUI bodies."""

from __future__ import annotations

import re
from typing import Iterable

CODE_SPAN_OR_WORD = re.compile(r"`[^`]*`[.,;:!?)]*|\S+")


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


def render_prose(paragraph: str, *, width: int, justify: bool) -> list[str]:
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


def render_body(body: str, *, width: int, justify: bool) -> list[str]:
    output: list[str] = []
    paragraph: list[str] = []

    def flush_paragraph() -> None:
        if not paragraph:
            return
        output.extend(render_prose(" ".join(paragraph), width=width, justify=justify))
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
