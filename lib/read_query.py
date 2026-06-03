#!/usr/bin/env -S uv run --script
"""Advanced read query — filters messages by date, outputs JSON."""
# /// script
# requires-python = ">=3.10"
# ///

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parse import format_message, parse_header, parse_messages, TIMESTAMP_FMT


def parse_date(s: str) -> datetime:
    for fmt in (TIMESTAMP_FMT, "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    print(f"Error: could not parse date: {s!r}", file=sys.stderr)
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("chat_file", type=Path)
    parser.add_argument("--cursor", type=int, default=0)
    parser.add_argument("--by", dest="sender")
    parser.add_argument("--exclude-sender")
    parser.add_argument("--after")
    parser.add_argument("--before")
    parser.add_argument("--last", type=int)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--markdown", action="store_true")
    parser.add_argument("--no-header", dest="no_header", action="store_true")
    parser.add_argument("--id", action="store_true")
    args = parser.parse_args()

    if not args.chat_file.exists():
        print(f"Error: file not found: {args.chat_file}", file=sys.stderr)
        sys.exit(1)

    messages = parse_messages(args.chat_file)

    # Filter by cursor (unread mode) — cursor is a 1-based message index
    if args.cursor > 0:
        messages = [m for m in messages if m.message_index > args.cursor]

    if args.sender:
        messages = [m for m in messages if m.sender.lower() == args.sender.lower()]
    if args.exclude_sender:
        messages = [m for m in messages if m.sender.lower() != args.exclude_sender.lower()]
    if args.after:
        after = parse_date(args.after)
        messages = [m for m in messages if m.timestamp >= after]
    if args.before:
        before = parse_date(args.before)
        messages = [m for m in messages if m.timestamp <= before]
    if args.last:
        messages = messages[-args.last:]

    if args.markdown:
        if not args.no_header:
            header = parse_header(args.chat_file)
            if header:
                print(header.rstrip())
        for msg in messages:
            print()
            print(format_message(msg))
        return

    if args.json:
        output = []
        for msg in messages:
            entry = {
                "sender": msg.sender,
                "timestamp": msg.timestamp_str,
                "body": msg.body,
                "preview": msg.preview,
                "index": msg.message_index,
            }
            if args.id:
                entry["id"] = msg.id
            output.append(entry)
        print(json.dumps(output, indent=2))
    else:
        if not messages:
            print("No messages matching filters.")
            return
        for msg in messages:
            id_str = f"  {msg.id}" if args.id else ""
            print(f"  {msg.timestamp_str}  {msg.sender:15s}  {msg.preview[:60]}{id_str}")


if __name__ == "__main__":
    main()
