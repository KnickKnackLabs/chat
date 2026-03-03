#!/usr/bin/env bash
# chat.sh — shared helpers for the agent chat CLI

CHAT_DATA_DIR="${CHAT_DATA_DIR:-$HOME/.local/share/chat}"
CHAT_DEFAULT="den"

# Resolve which chat we're targeting
# Usage: chat_resolve [name]
# Sets CHAT_NAME, CHAT_FILE, CHAT_CURSOR_DIR
chat_resolve() {
  CHAT_NAME="${1:-$CHAT_DEFAULT}"
  CHAT_FILE="$CHAT_DATA_DIR/${CHAT_NAME}.md"
  CHAT_CURSOR_DIR="$CHAT_DATA_DIR/.cursors/${CHAT_NAME}"
}

# Ensure chat infrastructure exists
chat_init() {
  mkdir -p "$CHAT_DATA_DIR" "$CHAT_CURSOR_DIR"
  if [ ! -f "$CHAT_FILE" ]; then
    cat > "$CHAT_FILE" <<EOF
# ${CHAT_NAME}

Shared communication channel. Keep messages short (<10 lines). For longer content, write to \`/tmp/chat-attachment-<timestamp>.md\` and reference it here.

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
  if [ -z "$agent" ]; then
    echo "Error: agent name required for chat_set_cursor" >&2
    return 1
  fi
  local count
  count=$(chat_line_count)
  printf '%s' "$count" > "$CHAT_CURSOR_DIR/$agent"
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

# List all available chats
chat_list() {
  local chats=()
  for f in "$CHAT_DATA_DIR"/*.md; do
    [ -f "$f" ] || continue
    chats+=("$(basename "$f" .md)")
  done
  printf '%s\n' "${chats[@]}"
}

# Format a message block for display using gum
# Usage: chat_format_message "header_line" "body_text"
chat_format_messages() {
  if ! command -v gum &>/dev/null; then
    # Fallback: plain output
    cat
    return
  fi

  local in_header=false
  local header=""
  local body=""
  local first=true

  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^###\ (.+)\ —\ (.+)$ ]]; then
      # Print previous message if any
      if [ -n "$header" ]; then
        _chat_render_block "$header" "$body" "$first"
        first=false
      fi
      header="${BASH_REMATCH[1]}  ${BASH_REMATCH[2]}"
      body=""
      in_header=true
    elif [ "$in_header" = true ]; then
      # Accumulate body (skip leading blank line after header)
      if [ -n "$body" ] || [ -n "$line" ]; then
        body+="${body:+$'\n'}${line}"
      fi
    fi
  done

  # Render last message
  if [ -n "$header" ]; then
    _chat_render_block "$header" "$body" "$first"
  fi
}

# Render a single message block with gum
_chat_render_block() {
  local header="$1"
  local body="$2"
  local is_first="$3"

  [ "$is_first" = "false" ] && echo ""

  gum style --foreground 39 --bold "$header"
  if [ -n "$body" ]; then
    echo "$body"
  fi
}
