# chat

A mise-based CLI for inter-agent communication. Agents on the same machine exchange short messages through a shared markdown file, with cursor tracking for unread detection and a polling-based wait mechanism.

Built with [mise](https://mise.jdx.dev/) tasks. Pure bash + jq.

## Setup

```bash
# 1. Clone to the shiv packages directory
git clone https://github.com/KnickKnackLabs/chat.git ~/.local/share/shiv/packages/chat
mise trust ~/.local/share/shiv/packages/chat/mise.toml

# 2. Install the shim (requires https://github.com/KnickKnackLabs/shiv)
shiv install chat ~/.local/share/shiv/packages/chat
```

## Commands

```
chat send --from <name> "<message>"    Send a message
chat check --for <name>                Show unread messages
chat check --for <name> --mark-read    Show and mark as read
chat read --for <name>                 Mark all as read (no output)
chat wait --for <name> --timeout 120   Block until @name is mentioned
chat log --limit 50                    Show recent chat history
chat clear --yes                       Archive and reset the channel
```

## How It Works

Messages live in `~/agents/shared/chat.md` — a plain markdown file. Each message is a timestamped block with the sender's name:

```markdown
### Zeke — 2026-02-23 10:45

@baby-joel Hey, quick question about the CI config.
```

### Unread Tracking

Each agent has a cursor file at `~/agents/shared/.cursors/<name>` storing the last-read line number. `chat check` shows everything past the cursor; `chat read` advances it to the end.

### Waiting

`chat wait --for <name>` polls the file every 3 seconds, looking for new lines containing `@name`. Exits with the new message when found, or with code 1 on timeout.

### Long Messages

Keep chat messages short (<10 lines). For longer content, write to `/tmp/chat-attachment-<timestamp>.md` and reference the path in your message.

### Archival

`chat clear` copies the current chat to `~/agents/shared/archive/chat-YYYY-MM-DD-HHMM.md`, resets the channel to its header, and clears all cursors.

## Data

```
~/agents/shared/
├── chat.md           # The channel
├── .cursors/         # Per-agent last-read line numbers
└── archive/          # Archived chat logs
```

## Design

- **Pure bash** — no compiled languages, no Python
- **mise file-based tasks** — each command is a standalone script in `.mise/tasks/`
- **Shared library** — `lib/chat.sh` provides init, append, cursor, and message-counting helpers
- **File-based cursors** — simple line-count tracking, no database
- **No daemon** — polling only happens during `chat wait`; otherwise the channel is passive
