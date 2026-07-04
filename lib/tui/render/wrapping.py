"""Paragraph wrapping and justification for chat TUI bodies."""

from __future__ import annotations

import math
import re
from typing import Iterable

CODE_SPAN_OR_WORD = re.compile(r"`[^`]*`[.,;:!?)]*|\S+")
LIST_ITEM_RE = re.compile(r"^(\s*)((?:[-*+]|\d+[.)])\s+)(.*)$")


def is_list_item(line: str) -> bool:
    return LIST_ITEM_RE.match(line) is not None


def is_markdownish(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return False
    if line.startswith((" ", "\t")):
        return True
    if stripped.startswith(("```", "~~~", ">", "#")):
        return True
    if "|" in stripped:
        return True
    if re.search(r"https?://\S+", stripped):
        return True
    return False


def is_list_boundary(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return True
    if is_list_item(line):
        return True
    if stripped.startswith(("```", "~~~", ">", "#")):
        return True
    if "|" in stripped:
        return True
    if re.search(r"https?://\S+", stripped):
        return True
    return False


def leading_whitespace(line: str) -> str:
    return line[: len(line) - len(line.lstrip(" \t"))]


def leading_whitespace_width(line: str) -> int:
    return len(leading_whitespace(line))


def tokenize(text: str) -> list[str]:
    return CODE_SPAN_OR_WORD.findall(text)


def tokens_length(tokens: list[str]) -> int:
    if not tokens:
        return 0
    return sum(len(token) for token in tokens) + len(tokens) - 1


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


def balanced_wrap_tokens(tokens: list[str], width: int) -> list[list[str]]:
    """Choose paragraph line breaks that avoid ugly justification gaps.

    This is a small dynamic-programming line breaker inspired by TeX's
    paragraph-level optimization, not a full Knuth-Plass implementation. It
    minimizes the total spacing "badness" over the paragraph instead of making
    each line greedily as full as possible.
    """

    if not tokens:
        return []

    token_count = len(tokens)
    lengths = [len(token) for token in tokens]
    prefix = [0]
    for length in lengths:
        prefix.append(prefix[-1] + length)

    def line_length(start: int, end: int) -> int:
        word_count = end - start
        return prefix[end] - prefix[start] + max(0, word_count - 1)

    def line_badness(start: int, end: int) -> float:
        length = line_length(start, end)
        word_count = end - start

        # A single over-wide token has no legal break inside this renderer.
        if length > width and word_count > 1:
            return math.inf

        slack = max(0, width - length)
        if end == token_count:
            # Last lines stay ragged. Penalize very short or orphan-ish final
            # lines lightly so we do not make prior justified lines terrible
            # just to fill the final line.
            if word_count == 1 and token_count > 1:
                return slack * slack * 2
            return slack * slack * 0.1

        gaps = word_count - 1
        if gaps == 0:
            return math.inf

        max_extra_per_gap = math.ceil(slack / gaps) if gaps else slack
        # Combining total slack and worst-gap penalty discourages visible
        # "rivers" while still preferring a filled text column.
        return slack * slack + (max_extra_per_gap**4 * 8)

    best_cost = [math.inf] * (token_count + 1)
    next_break = [token_count] * (token_count + 1)
    best_cost[token_count] = 0

    for start in range(token_count - 1, -1, -1):
        for end in range(start + 1, token_count + 1):
            length = line_length(start, end)
            if length > width and end - start > 1:
                break

            cost = line_badness(start, end) + best_cost[end]
            if cost < best_cost[start]:
                best_cost[start] = cost
                next_break[start] = end

    if math.isinf(best_cost[0]):
        return wrap_tokens(tokens, width)

    lines: list[list[str]] = []
    start = 0
    while start < token_count:
        end = next_break[start]
        lines.append(tokens[start:end])
        start = end
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


def render_prose(
    paragraph: str,
    *,
    width: int,
    justify: bool,
    justify_style: str = "balanced",
) -> list[str]:
    tokens = tokenize(paragraph)
    if justify and justify_style == "balanced":
        wrapped = balanced_wrap_tokens(tokens, width)
    else:
        wrapped = wrap_tokens(tokens, width)
    if not wrapped:
        return []

    lines: list[str] = []
    last_index = len(wrapped) - 1
    for index, line_tokens in enumerate(wrapped):
        if justify and index != last_index:
            lines.append(justify_tokens(line_tokens, width))
        else:
            lines.append(" ".join(line_tokens))
    return lines


def render_list_item(
    prefix: str,
    text: str,
    *,
    width: int,
    justify: bool,
    justify_style: str,
) -> list[str]:
    content_width = max(1, width - len(prefix))
    content_lines = render_prose(
        text,
        width=content_width,
        justify=justify,
        justify_style=justify_style,
    )
    if not content_lines:
        return [prefix.rstrip()]

    continuation = " " * len(prefix)
    return [
        f"{prefix}{content_lines[0]}",
        *(f"{continuation}{line}" for line in content_lines[1:]),
    ]


def render_body(
    body: str,
    *,
    width: int,
    justify: bool,
    justify_style: str = "balanced",
) -> list[str]:
    output: list[str] = []
    paragraph: list[str] = []
    list_prefix = ""
    list_lines: list[str] = []

    def flush_paragraph() -> None:
        if not paragraph:
            return
        output.extend(
            render_prose(
                " ".join(paragraph),
                width=width,
                justify=justify,
                justify_style=justify_style,
            )
        )
        paragraph.clear()

    def flush_list_item() -> None:
        nonlocal list_prefix
        if not list_prefix:
            return
        output.extend(
            render_list_item(
                list_prefix,
                " ".join(list_lines),
                width=width,
                justify=justify,
                justify_style=justify_style,
            )
        )
        list_prefix = ""
        list_lines.clear()

    for raw_line in body.splitlines():
        if raw_line.strip() == "":
            flush_paragraph()
            flush_list_item()
            output.append("")
            continue

        list_match = LIST_ITEM_RE.match(raw_line)
        if list_match:
            flush_paragraph()
            if list_prefix:
                flush_list_item()
                output.append("")
            leading, marker, text = list_match.groups()
            list_prefix = f"{leading}{marker}"
            list_lines.append(text.strip())
            continue

        if (
            list_prefix
            and raw_line.startswith((" ", "\t"))
            and "\t" not in leading_whitespace(raw_line)
            and leading_whitespace_width(raw_line) <= len(list_prefix)
            and not is_list_boundary(raw_line)
        ):
            list_lines.append(raw_line.strip())
            continue

        if is_markdownish(raw_line):
            flush_paragraph()
            flush_list_item()
            output.append(raw_line.rstrip())
            continue

        flush_list_item()
        paragraph.append(raw_line.strip())

    flush_paragraph()
    flush_list_item()
    return output
