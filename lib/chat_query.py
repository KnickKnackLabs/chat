#!/usr/bin/env -S uv run --script
"""Single source of truth for message-boundary queries.

Called by Bash helpers in chat.sh to replace naive grep/awk with the
parser's disambiguation-aware logic.  Every query here uses the same
state-machine parser that the Python `parse_messages` uses, so body
content that happens to contain ``from:``, ``id:``, ``ts:`` or ``---``
alone is never mistaken for a message boundary.
"""
# /// script
# requires-python = ">=3.10"
# ///

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parse import ChatFormatError, parse_messages, _is_block_open


# Map frontmatter field names to Message dataclass attributes.
_FIELD_ATTR = {
    "from": "sender",
    "ts": "timestamp_str",
    "to": "to",
    "id": "id",
    "src": "source",
}


def _find_block_ranges(text: str) -> list[tuple[int, int]]:
    """Return (start_line, end_line_exclusive) for every message block.

    Each range spans from the opening ``---`` through the last body line,
    so callers can extract raw file content for a set of messages.
    """
    lines = text.split("\n")
    n = len(lines)
    ranges: list[tuple[int, int]] = []
    i = 0
    while i < n:
        if _is_block_open(lines, i):
            start = i
            i += 1
            # Skip frontmatter fields until the closing ---
            while i < n and lines[i].strip() != "---":
                i += 1
            if i < n:
                i += 1  # skip closing ---
            # Body lines until the next block opens
            while i < n and not _is_block_open(lines, i):
                i += 1
            ranges.append((start, i))
        else:
            i += 1
    return ranges


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Frontmatter-aware message queries for the chat library."
    )
    parser.add_argument("file", type=Path, help="Chat markdown file to query")
    parser.add_argument(
        "--count", action="store_true", help="Print the number of messages"
    )
    parser.add_argument(
        "--participants", action="store_true", help="List unique sender names"
    )
    parser.add_argument(
        "--last-field",
        choices=["from", "ts", "to", "id", "src"],
        help="Get the value of a frontmatter field from the last message",
    )
    parser.add_argument(
        "--messages-after",
        type=int,
        metavar="CURSOR",
        help="Emit raw frontmatter blocks for messages whose index > CURSOR",
    )
    parser.add_argument(
        "--count-after",
        type=int,
        metavar="CURSOR",
        help="Count messages whose index > CURSOR",
    )
    parser.add_argument(
        "--exclude-sender",
        help="Exclude a sender from --count-after results",
    )
    args = parser.parse_args()

    if not args.file.exists():
        # No file — nothing to query.  Return 0 for count modes, nothing for
        # others.  Consistent with the old grep-'^from: '-on-missing-file
        # behaviour (where ``grep -c`` returned 0).
        if args.count:
            print(0)
        return

    text = args.file.read_text()
    try:
        messages = parse_messages(args.file)
    except ChatFormatError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)

    if args.count:
        print(len(messages))

    elif args.participants:
        senders = sorted(set(m.sender.lower() for m in messages))
        for s in senders:
            print(s)

    elif args.last_field:
        if messages:
            attr = _FIELD_ATTR.get(args.last_field, args.last_field)
            val = getattr(messages[-1], attr, None)
            if val is not None:
                print(val)

    elif args.messages_after is not None:
        ranges = _find_block_ranges(text)
        lines = text.split("\n")
        out_lines: list[str] = []
        for idx, (start, end) in enumerate(ranges, start=1):
            if idx > args.messages_after:
                out_lines.extend(lines[start:end])
        if out_lines:
            # Ensure exactly one trailing newline for pipe consumers
            # (chat_format_messages, etc.).
            sys.stdout.write("\n".join(out_lines) + "\n")

    elif args.count_after is not None:
        exclude = (
            args.exclude_sender.lower() if args.exclude_sender else None
        )
        count = sum(
            1
            for m in messages
            if m.message_index > args.count_after
            and (exclude is None or m.sender.lower() != exclude)
        )
        print(count)


if __name__ == "__main__":
    main()