"""
Chat message parser — structured access to chat markdown files.

Each message is a YAML-frontmatter block followed by a markdown body:

    ---
    id: 1
    from: alice
    ts: 2026-03-25 12:05
    to: bob          # optional
    src: ops         # optional (origin channel, for merges)
    ---
    message body, which may span
    multiple lines.

Disambiguation rule: a line consisting solely of `---` begins a new
message only if the immediately following line matches `^(id|from|ts):`.
Otherwise the `---` is treated as body content, so message bodies may
contain horizontal rules without confusing the parser.

Cursors address messages by **index** (1-based position in the file),
not by line number — editing a message body never shifts another
message's index.
"""

import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional


TIMESTAMP_FMT = "%Y-%m-%d %H:%M"
# Accepted on-disk timestamp layouts (first one is canonical for output).
_TS_FORMATS = (TIMESTAMP_FMT, "%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M:%S")

DELIM = "---"
# A `---` opens a frontmatter block only when the next line starts with one
# of these keys — this is the body/horizontal-rule disambiguation rule.
FM_OPEN_KEY_RE = re.compile(r"^(id|from|ts):\s")
# A single "key: value" frontmatter line.
FM_FIELD_RE = re.compile(r"^([A-Za-z_][\w-]*):\s?(.*)$")


class ChatFormatError(ValueError):
    """Raised when a chat file is not in the expected frontmatter format."""


def _has_payload_after_preamble_separator(lines: list[str]) -> bool:
    """Return True when a no-message file has nonblank data after its separator."""
    separator = None
    for i, line in enumerate(lines):
        if line.strip() == DELIM:
            separator = i
    if separator is None:
        return False
    return any(line.strip() for line in lines[separator + 1:])


def _parse_timestamp(raw: str) -> datetime:
    for fmt in _TS_FORMATS:
        try:
            return datetime.strptime(raw.strip(), fmt)
        except ValueError:
            continue
    # Last resort: ISO parsing (handles offsets / microseconds).
    return datetime.fromisoformat(raw.strip())


@dataclass
class Message:
    sender: str
    timestamp: datetime
    body: str
    message_index: int           # 1-based position in the file
    id: Optional[int] = None     # explicit `id:` field; defaults to index
    to: Optional[str] = None     # optional recipient
    source: Optional[str] = None # origin channel (for merges)

    @property
    def preview(self) -> str:
        """First non-empty line of body, truncated to 80 chars."""
        for line in self.body.strip().split("\n"):
            if line.strip():
                return line.strip()[:80]
        return ""

    @property
    def timestamp_str(self) -> str:
        return self.timestamp.strftime(TIMESTAMP_FMT)


def _is_block_open(lines: list[str], i: int) -> bool:
    """True if lines[i] opens a frontmatter block (per the disambiguation rule)."""
    return (
        lines[i].strip() == DELIM
        and i + 1 < len(lines)
        and bool(FM_OPEN_KEY_RE.match(lines[i + 1]))
    )


def _first_block_index(lines: list[str]) -> Optional[int]:
    for i in range(len(lines)):
        if _is_block_open(lines, i):
            return i
    return None


def parse_header(filepath: Path) -> str:
    """Everything before the first message block (the channel preamble)."""
    lines = filepath.read_text().split("\n")
    start = _first_block_index(lines)
    if start is None:
        return filepath.read_text()  # no messages — whole file is header
    return "\n".join(lines[:start])


def parse_messages(filepath: Path, source: Optional[str] = None) -> list[Message]:
    """Parse a chat markdown file into a list of Message objects."""
    lines = filepath.read_text().split("\n")
    n = len(lines)
    messages: list[Message] = []

    i = _first_block_index(lines)
    if i is None:
        if _has_payload_after_preamble_separator(lines):
            raise ChatFormatError(f"invalid chat file format: {filepath}")
        return messages

    index = 0
    while i < n:
        # lines[i] is a block-opening `---`
        i += 1
        fields: dict[str, str] = {}
        while i < n and lines[i].strip() != DELIM:
            m = FM_FIELD_RE.match(lines[i])
            if m:
                fields[m.group(1).lower()] = m.group(2).strip()
            i += 1
        if i >= n:
            raise ChatFormatError(f"invalid chat file format: {filepath}")
        i += 1  # skip the closing `---`

        if not fields.get("id") or not fields.get("from") or not fields.get("ts"):
            raise ChatFormatError(f"invalid chat file format: {filepath}")

        body_lines: list[str] = []
        while i < n and not _is_block_open(lines, i):
            body_lines.append(lines[i])
            i += 1

        index += 1
        raw_id = fields.get("id")
        try:
            msg_id = int(raw_id) if raw_id is not None else index
        except ValueError:
            msg_id = index
        ts_raw = fields.get("ts", "")
        messages.append(Message(
            sender=fields.get("from", ""),
            timestamp=_parse_timestamp(ts_raw) if ts_raw else datetime.min,
            body=_clean_body(body_lines),
            message_index=index,
            id=msg_id,
            to=fields.get("to") or None,
            source=fields.get("src") or source,
        ))

    return messages


def format_message(msg: Message, tag_source: bool = False) -> str:
    """Format a Message as an on-disk frontmatter block (no trailing newline)."""
    head = [DELIM, f"id: {msg.id if msg.id is not None else msg.message_index}",
            f"from: {msg.sender}", f"ts: {msg.timestamp_str}"]
    if msg.to:
        head.append(f"to: {msg.to}")
    if tag_source and msg.source:
        head.append(f"src: {msg.source}")
    head.append(DELIM)
    return "\n".join(head) + "\n" + msg.body


def merge_messages(
    channels: dict[str, Path],
    tag_sources: bool = True,
) -> tuple[str, list[Message]]:
    """
    Merge multiple channels into a single timestamp-sorted message list.

    Returns (header, sorted_messages) — header taken from the first channel.
    Fresh sequential ids are assigned at write time (see write_chat).
    """
    all_messages: list[Message] = []
    header: Optional[str] = None

    for name, path in channels.items():
        if header is None:
            header = parse_header(path)
        all_messages.extend(parse_messages(path, source=name))

    all_messages.sort(key=lambda m: m.timestamp)
    return header or "", all_messages


def write_chat(
    filepath: Path,
    header: str,
    messages: list[Message],
    tag_sources: bool = True,
) -> None:
    """Write a complete chat file, assigning fresh sequential ids/indices."""
    parts = [header.rstrip()]
    for i, msg in enumerate(messages, start=1):
        msg.id = i
        msg.message_index = i
        parts.append("")  # blank line separator between blocks
        parts.append(format_message(msg, tag_source=tag_sources))
    filepath.write_text("\n".join(parts) + "\n")


def _clean_body(lines: list[str]) -> str:
    """Strip leading/trailing blank lines from a message body."""
    while lines and not lines[0].strip():
        lines = lines[1:]
    while lines and not lines[-1].strip():
        lines = lines[:-1]
    return "\n".join(lines)
