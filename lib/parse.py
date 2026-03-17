"""
Chat message parser — structured access to chat markdown files.

Parses the ### sender — YYYY-MM-DD HH:MM message format into
Message objects with sender, timestamp, body, and metadata.
"""

import hashlib
import re
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Optional


MESSAGE_HEADER_RE = re.compile(
    r"^### (.+?) — (\d{4}-\d{2}-\d{2} \d{2}:\d{2})(.*)$"
)
TIMESTAMP_FMT = "%Y-%m-%d %H:%M"


@dataclass
class Message:
    sender: str
    timestamp: datetime
    body: str
    line_number: int
    source: Optional[str] = None  # origin channel (for merges)

    @property
    def id(self) -> str:
        """Stable message ID — hash of sender + timestamp + first body line."""
        first_line = self.body.strip().split("\n")[0] if self.body.strip() else ""
        key = f"{self.sender}|{self.timestamp.isoformat()}|{first_line}"
        return hashlib.sha256(key.encode()).hexdigest()[:12]

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


def parse_header(filepath: Path) -> Optional[str]:
    """Extract the chat file header (everything before the first message)."""
    text = filepath.read_text()
    # Find first message header
    for i, line in enumerate(text.split("\n")):
        if MESSAGE_HEADER_RE.match(line):
            return "\n".join(text.split("\n")[:i])
    return text  # no messages — entire file is header


def parse_messages(filepath: Path, source: Optional[str] = None) -> list[Message]:
    """Parse a chat markdown file into a list of Message objects."""
    messages = []
    lines = filepath.read_text().split("\n")

    current_sender = None
    current_timestamp = None
    current_body_lines: list[str] = []
    current_line_number = 0
    header_suffix = ""

    for i, line in enumerate(lines, start=1):
        match = MESSAGE_HEADER_RE.match(line)
        if match:
            # Save previous message
            if current_sender is not None:
                body = _clean_body(current_body_lines)
                messages.append(Message(
                    sender=current_sender,
                    timestamp=current_timestamp,
                    body=body,
                    line_number=current_line_number,
                    source=source,
                ))
            # Start new message
            current_sender = match.group(1)
            current_timestamp = datetime.strptime(match.group(2), TIMESTAMP_FMT)
            header_suffix = match.group(3).strip()
            current_body_lines = []
            current_line_number = i
        elif current_sender is not None:
            current_body_lines.append(line)

    # Don't forget the last message
    if current_sender is not None:
        body = _clean_body(current_body_lines)
        messages.append(Message(
            sender=current_sender,
            timestamp=current_timestamp,
            body=body,
            line_number=current_line_number,
            source=source,
        ))

    return messages


def format_message(msg: Message, tag_source: bool = False) -> str:
    """Format a Message back into chat markdown."""
    header = f"### {msg.sender} — {msg.timestamp_str}"
    if tag_source and msg.source:
        header += f" \u27f5 {msg.source}"
    return f"\n{header}\n\n{msg.body}"


def merge_messages(
    channels: dict[str, Path],
    tag_sources: bool = True,
) -> tuple[str, list[Message]]:
    """
    Merge multiple channels into a single sorted message list.

    Args:
        channels: mapping of channel_name -> filepath
        tag_sources: if True, annotate messages with origin channel

    Returns:
        (header, sorted_messages) — header from the first channel
    """
    all_messages: list[Message] = []
    header = None

    for name, path in channels.items():
        if header is None:
            header = parse_header(path)
        msgs = parse_messages(path, source=name)
        all_messages.extend(msgs)

    # Stable sort by timestamp (preserves order within same timestamp)
    all_messages.sort(key=lambda m: m.timestamp)

    return header or "", all_messages


def write_chat(
    filepath: Path,
    header: str,
    messages: list[Message],
    tag_sources: bool = True,
) -> None:
    """Write a complete chat file from header + messages."""
    parts = [header.rstrip()]
    for msg in messages:
        parts.append(format_message(msg, tag_source=tag_sources))
    filepath.write_text("\n".join(parts) + "\n")


def _clean_body(lines: list[str]) -> str:
    """Strip leading/trailing blank lines from message body."""
    # Strip leading blank lines
    while lines and not lines[0].strip():
        lines = lines[1:]
    # Strip trailing blank lines
    while lines and not lines[-1].strip():
        lines = lines[:-1]
    return "\n".join(lines)
