#!/usr/bin/env bash
# chat.sh — shared helpers for the agent chat CLI

CHAT_DATA_DIR="${CHAT_DATA_DIR:-$HOME/.local/share/chat}"

# Determine the repo root from this library's location.  Do not read mise's
# task-only config-root env here; agent shells can inherit a stale value.
CHAT_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Resolve the caller's identity
# Priority: explicit flag > $CHAT_IDENTITY env var > empty (spectator)
# Usage: chat_resolve_identity [explicit_name]
# Sets CHAT_IDENTITY (global)
chat_resolve_identity() {
  if [ -n "${1:-}" ]; then
    CHAT_IDENTITY="$1"
  else
    CHAT_IDENTITY="${CHAT_IDENTITY:-}"
  fi
}

# Resolve identity or fail — for commands that require it
# Usage: chat_require_identity [explicit_name]
chat_require_identity() {
  chat_resolve_identity "${1:-}"
  if [ -z "$CHAT_IDENTITY" ]; then
    echo "Error: identity required. Use --as <name> or set \$CHAT_IDENTITY." >&2
    return 1
  fi
}

# Resolve which chat we're targeting.
# Priority: explicit name > $CHAT_CHANNEL env var > "default"
# Usage: chat_resolve [name]
# Sets CHAT_NAME, CHAT_FILE, CHAT_CURSOR_DIR, CHAT_NAME_SOURCE
# CHAT_NAME_SOURCE records where the name came from (explicit|env|default) so
# read-only commands can tell "you named a channel that's missing" apart from
# "no channel was specified or inferred".
chat_resolve() {
  if [ -n "${1:-}" ]; then
    CHAT_NAME="$1"
    CHAT_NAME_SOURCE="explicit"
  elif [ -n "${CHAT_CHANNEL:-}" ]; then
    CHAT_NAME="$CHAT_CHANNEL"
    CHAT_NAME_SOURCE="env"
  else
    CHAT_NAME="default"
    CHAT_NAME_SOURCE="default"
  fi
  CHAT_FILE="$CHAT_DATA_DIR/${CHAT_NAME}.md"
  CHAT_CURSOR_DIR="$CHAT_DATA_DIR/.cursors/${CHAT_NAME}"
}

# Require that the chat file already exists — for read-only commands
chat_require_file() {
  if [ ! -f "$CHAT_FILE" ]; then
    # No channel was named or inferred — don't point at the phantom default.
    if [ "${CHAT_NAME_SOURCE:-explicit}" = "default" ]; then
      echo "Error: no chat channel specified and no default channel could be inferred." >&2
      echo "Pass a channel name or set \$CHAT_CHANNEL (e.g. chat read den --as ikma)." >&2
    else
      echo "Error: chat '${CHAT_NAME}' does not exist." >&2
      echo "Create it by sending a message: chat send --chat ${CHAT_NAME} --as <name> \"hello\"" >&2
    fi
    return 1
  fi
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

# Delegate to the Python parser for message-boundary-aware counting.
# This respects the disambiguation rule (``---`` followed by id/from/ts),
# so body content that happens to contain ``from:`` is never miscounted.
chat_message_count() {
  local file="${1:-$CHAT_FILE}"
  uv run --script "$CHAT_REPO_ROOT/lib/chat_query.py" "$file" --count
}

# Value of a frontmatter field on the last message of a file ("" if none).
# Usage: chat_last_field <file> <field>   (field is one of from|ts|to|id|src)
chat_last_field() {
  local file="$1" field="$2"
  if ! uv run --script "$CHAT_REPO_ROOT/lib/chat_query.py" "$file" --last-field "$field" 2>/dev/null; then
    return 0
  fi
}

# Unique, lowercase, sorted list of senders in a file (one per line).
chat_participants() {
  local file="$1"
  if ! uv run --script "$CHAT_REPO_ROOT/lib/chat_query.py" "$file" --participants 2>/dev/null; then
    return 0
  fi
}

# Get the cursor (index of the last-read message) for an agent
chat_get_cursor() {
  local agent="$1"
  local cursor_file="$CHAT_CURSOR_DIR/$agent"
  if [ -f "$cursor_file" ]; then
    cat "$cursor_file"
  else
    echo "0"
  fi
}

# Set the cursor for an agent to the current message count
chat_set_cursor() {
  local agent="$1"
  if [ -z "$agent" ]; then
    echo "Error: agent name required for chat_set_cursor" >&2
    return 1
  fi
  local cursor_file="$CHAT_CURSOR_DIR/$agent"
  local count previous
  if ! count=$(chat_message_count); then
    return 1
  fi
  if [ -f "$cursor_file" ]; then
    previous=$(cat "$cursor_file")
    if [ "$previous" != "$count" ]; then
      printf '%s' "$previous" > "${cursor_file}.prev"
    fi
  fi
  printf '%s' "$count" > "$cursor_file"
}

# Format a timestamp
chat_timestamp() {
  date "+%Y-%m-%d %H:%M"
}

# Convert "YYYY-MM-DD HH:MM" to epoch seconds (portable: macOS + Linux)
_chat_to_epoch() {
  local ts="$1"
  if date --version &>/dev/null 2>&1; then
    # GNU date (Linux)
    date -d "$ts" +%s 2>/dev/null
  else
    # BSD date (macOS) — needs explicit format
    date -j -f "%Y-%m-%d %H:%M" "$ts" +%s 2>/dev/null
  fi
}

# Format a timestamp as relative time (e.g., "2d ago", "3h ago", "just now")
# Usage: chat_relative_time "2026-03-23 14:30"
chat_relative_time() {
  local ts="$1"
  [ -z "$ts" ] && return

  local then_epoch now_epoch diff
  then_epoch=$(_chat_to_epoch "$ts") || { echo "$ts"; return; }
  now_epoch=$(date +%s)
  diff=$(( now_epoch - then_epoch ))

  if [ "$diff" -lt 0 ]; then
    echo "$ts"
  elif [ "$diff" -lt 60 ]; then
    echo "just now"
  elif [ "$diff" -lt 3600 ]; then
    echo "$(( diff / 60 ))m ago"
  elif [ "$diff" -lt 86400 ]; then
    echo "$(( diff / 3600 ))h ago"
  elif [ "$diff" -lt 604800 ]; then
    echo "$(( diff / 86400 ))d ago"
  elif [ "$diff" -lt 2592000 ]; then
    echo "$(( diff / 604800 ))w ago"
  else
    echo "$ts"
  fi
}

# Append a message to the chat file as a frontmatter block.
# Usage: chat_append <from> <message> [to]
chat_append() {
  local from="$1"
  local message="$2"
  local to="${3:-}"

  local ts id count
  ts=$(chat_timestamp)
  if ! count=$(chat_message_count); then
    return 1
  fi
  id=$(( count + 1 ))

  {
    printf '\n%s\n' '---'
    printf 'id: %s\n' "$id"
    printf 'from: %s\n' "$from"
    printf 'ts: %s\n' "$ts"
    [ -n "$to" ] && printf 'to: %s\n' "$to"
    printf '%s\n' '---'
    printf '%s\n' "$message"
  } >> "$CHAT_FILE"
}

# Emit raw frontmatter blocks for messages with index > the given cursor.
# Uses the Python parser's disambiguation rule, so body content that
# happens to start with ``id:`` is never mistaken for a block opener.
_chat_messages_after() {
  local cursor="$1"
  uv run --script "$CHAT_REPO_ROOT/lib/chat_query.py" "$CHAT_FILE" --messages-after "$cursor"
}

# Count messages with index > the given cursor, excluding sender `self`
# (pass an empty self to count everyone).
_chat_count_after() {
  local cursor="$1" self="$2"
  local args=("$CHAT_FILE" --count-after "$cursor")
  [ -n "$self" ] && args+=(--exclude-sender "$self")
  uv run --script "$CHAT_REPO_ROOT/lib/chat_query.py" "${args[@]}"
}

# Get new messages (raw frontmatter blocks) since an agent's cursor.
# Returns 1 (and no output) when there is nothing new.
chat_new_messages() {
  local agent="$1"
  local cursor total
  cursor=$(chat_get_cursor "$agent")
  if ! total=$(chat_message_count); then
    return 1
  fi

  if [ "$cursor" -ge "$total" ]; then
    return 1  # no new messages
  fi

  _chat_messages_after "$cursor"
  return 0
}

# Count new messages since cursor, excluding the agent's own messages —
# your own unread messages shouldn't block you from sending.
chat_count_new() {
  local agent="$1"
  _chat_count_after "$(chat_get_cursor "$agent")" "$agent"
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

# Trim trailing blank lines from a string
# Usage: result=$(_chat_trim_trailing_newlines "$text")
_chat_trim_trailing_newlines() {
  local text="$1"
  while [[ "$text" =~ $'\n'$ ]]; do text="${text%$'\n'}"; done
  printf '%s' "$text"
}

# Render frontmatter-block messages (from stdin) for display using gum.
# Falls back to plain passthrough when gum is unavailable.
chat_format_messages() {
  if ! command -v gum &>/dev/null; then
    cat
    return
  fi

  local lines=()
  while IFS= read -r _chat_line; do
    lines+=("$_chat_line")
  done
  local n=${#lines[@]}
  local i=0 first=true

  # A block opens on a `---` whose next line is an id/from/ts field.
  _is_open() {
    [ "${lines[$1]}" = "---" ] && [ $(($1 + 1)) -lt "$n" ] \
      && [[ "${lines[$(($1 + 1))]}" =~ ^(id|from|ts): ]]
  }

  # Skip the channel header — advance to the first message block.
  while [ "$i" -lt "$n" ] && ! _is_open "$i"; do i=$((i + 1)); done

  while [ "$i" -lt "$n" ]; do
    # lines[i] is the opening `---`; read frontmatter until the closing `---`.
    i=$((i + 1))
    local from="" ts=""
    while [ "$i" -lt "$n" ] && [ "${lines[$i]}" != "---" ]; do
      case "${lines[$i]}" in
        "from: "*) from="${lines[$i]#from: }" ;;
        "ts: "*)   ts="${lines[$i]#ts: }" ;;
      esac
      i=$((i + 1))
    done
    i=$((i + 1))  # skip the closing `---`

    # Body runs until the next block opens (or EOF).
    local body=""
    while [ "$i" -lt "$n" ] && ! _is_open "$i"; do
      if [ -n "$body" ] || [ -n "${lines[$i]}" ]; then
        body+="${body:+$'\n'}${lines[$i]}"
      fi
      i=$((i + 1))
    done
    body=$(_chat_trim_trailing_newlines "$body")
    _chat_render_block "${from}  ${ts}" "$body" "$first"
    first=false
  done
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
