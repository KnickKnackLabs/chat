#!/usr/bin/env bash
# chat.sh — shared helpers for the agent chat CLI

CHAT_DIR="$HOME/agents/shared"
CHAT_FILE="$CHAT_DIR/chat.md"
CHAT_CURSOR_DIR="$CHAT_DIR/.cursors"

# Ensure chat infrastructure exists
chat_init() {
  mkdir -p "$CHAT_DIR" "$CHAT_CURSOR_DIR"
  if [ ! -f "$CHAT_FILE" ]; then
    cat > "$CHAT_FILE" <<'EOF'
# Agent Chat

Shared communication channel between agents. Keep messages short (<10 lines). For longer content, write to `/tmp/chat-attachment-<timestamp>.md` and reference it here.

---
EOF
  fi
}

# Get the current line count of the chat file
chat_line_count() {
  wc -l < "$CHAT_FILE" | tr -d ' '
}

# Get the cursor (last-read line) for an agent
chat_get_cursor() {
  local agent="$1"
  local cursor_file="$CHAT_CURSOR_DIR/$agent"
  if [ -f "$cursor_file" ]; then
    cat "$cursor_file"
  else
    echo "0"
  fi
}

# Set the cursor for an agent to current line count
chat_set_cursor() {
  local agent="$1"
  chat_line_count > "$CHAT_CURSOR_DIR/$agent"
}

# Format a timestamp
chat_timestamp() {
  date "+%Y-%m-%d %H:%M"
}

# Append a message to the chat file
chat_append() {
  local from="$1"
  local message="$2"
  local ts
  ts=$(chat_timestamp)

  cat >> "$CHAT_FILE" <<EOF

### ${from} — ${ts}

${message}
EOF
}

# Get new messages since cursor for an agent
chat_new_messages() {
  local agent="$1"
  local cursor
  cursor=$(chat_get_cursor "$agent")
  local total
  total=$(chat_line_count)

  if [ "$cursor" -ge "$total" ]; then
    return 1  # no new messages
  fi

  tail -n +"$((cursor + 1))" "$CHAT_FILE"
  return 0
}

# Count new message blocks since cursor
chat_count_new() {
  local agent="$1"
  local cursor
  cursor=$(chat_get_cursor "$agent")
  local total
  total=$(chat_line_count)

  if [ "$cursor" -ge "$total" ]; then
    echo "0"
    return
  fi

  tail -n +"$((cursor + 1))" "$CHAT_FILE" | grep -c '^### ' || echo "0"
}
