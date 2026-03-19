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
from parse import parse_messages, TIMESTAMP_FMT


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
    parser.add_argument("--from", dest="sender")
    parser.add_argument("--after")
    parser.add_argument("--before")
    parser.add_argument("--last", type=int)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--id", action="store_true")
    args = parser.parse_args()

    if not args.chat_file.exists():
        print(f"Error: file not found: {args.chat_file}", file=sys.stderr)
        sys.exit(1)

    messages = parse_messages(args.chat_file)

    # Filter by cursor (unread mode)
    if args.cursor > 0:
        messages = [m for m in messages if m.line_number > args.cursor]

    if args.sender:
        messages = [m for m in messages if m.sender.lower() == args.sender.lower()]
    if args.after:
        after = parse_date(args.after)
        messages = [m for m in messages if m.timestamp >= after]
    if args.before:
        before = parse_date(args.before)
        messages = [m for m in messages if m.timestamp <= before]
    if args.last:
        messages = messages[-args.last:]

    if args.json:
        output = []
        for msg in messages:
            entry = {
                "sender": msg.sender,
                "timestamp": msg.timestamp_str,
                "body": msg.body,
                "preview": msg.preview,
                "line": msg.line_number,
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
