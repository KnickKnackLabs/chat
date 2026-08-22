#!/usr/bin/env bats
# Task-level integration tests — exercise actual task scripts via chat() shim
#
# API v2: --as replaces --for/--from, implicit identity via $CHAT_IDENTITY,
# read absorbs check/log/messages, welcome renamed to status.

load test_helper

@test "task list --json: outputs valid JSON array" {
  send_message "alice" "hello"
  run chat list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)"
}

@test "task list --json: includes channel name and msg count" {
  send_message "alice" "msg1"
  send_message "bob" "msg2"
  run chat list --json
  [ "$status" -eq 0 ]
  local entry
  entry=$(echo "$output" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
for c in channels:
    if c['name'] == 'test-chat':
        print(c['msgs'])
        break
")
  [ "$entry" = "2" ]
}

@test "task list --json: includes last_sender and last_time" {
  send_message "bob" "latest"
  run chat list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
for c in channels:
    if c['name'] == 'test-chat':
        assert c['last_sender'] == 'bob', f'expected bob, got {c[\"last_sender\"]}'
        assert c['last_time'] != '', 'last_time should not be empty'
        break
"
}

@test "task list --json: empty channel included with --all" {
  # test-chat exists but has no messages (only the header from chat_init)
  run chat list --json --all
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
for c in channels:
    if c['name'] == 'test-chat':
        assert c['msgs'] == 0, f'expected 0 msgs, got {c[\"msgs\"]}'
        assert c['last_sender'] == '', f'expected empty sender, got {c[\"last_sender\"]}'
        break
"
}

@test "task list --json: empty channel excluded by default" {
  # test-chat has no messages — should not appear without --all
  run chat list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
names = [c['name'] for c in channels]
assert 'test-chat' not in names, f'empty channel should be hidden, got: {names}'
"
}

@test "task list: human-readable output has no Lines column" {
  send_message "alice" "hello"
  run chat list
  [ "$status" -eq 0 ]
  # Should NOT contain "Lines" header
  ! [[ "$output" == *"Lines"* ]]
}

@test "task list: last activity shows relative time" {
  send_message "alice" "hello"
  run chat list
  [ "$status" -eq 0 ]
  # Should contain relative time (message was just sent, so "just now")
  [[ "$output" == *"just now"* ]]
}

@test "task list: last activity shows only time, not sender" {
  send_message "alice" "hello"
  run chat list
  [ "$status" -eq 0 ]
  # The Last Active column should NOT contain "alice —"
  ! [[ "$output" =~ alice\ — ]]
}

@test "task list: last activity does not show raw YYYY-MM-DD timestamp" {
  send_message "alice" "hello"
  run chat list
  [ "$status" -eq 0 ]
  local year
  year=$(date +%Y)
  ! [[ "$output" =~ test-chat.*${year}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2} ]]
}

@test "task list --json: last_time is raw timestamp not relative" {
  send_message "alice" "hello"
  run chat list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys, re
channels = json.load(sys.stdin)
for c in channels:
    if c['name'] == 'test-chat':
        assert re.match(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}', c['last_time']), \
            f'expected raw timestamp, got: {c[\"last_time\"]}'
        break
"
}

@test "task list: empty channels hidden by default" {
  # test-chat has no messages — shouldn't appear
  # Create a second chat WITH messages
  chat_resolve "active-chat"
  chat_init
  chat_append "alice" "hello"
  run chat list
  [ "$status" -eq 0 ]
  [[ "$output" == *"active-chat"* ]]
  ! [[ "$output" == *"test-chat"* ]]
}

@test "task list: empty channels shown with --all" {
  run chat list --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-chat"* ]]
}

@test "task list: sorted by most recent activity first" {
  # Create two chats with messages at explicitly different timestamps
  local older_file="$CHAT_DATA_DIR/older-chat.md"
  local newer_file="$CHAT_DATA_DIR/newer-chat.md"
  mkdir -p "$CHAT_DATA_DIR/.cursors/older-chat" "$CHAT_DATA_DIR/.cursors/newer-chat"

  cat > "$older_file" <<'OLDER_CHAT'
# older-chat

---

### alice — 2025-01-01 10:00

old message
OLDER_CHAT

  cat > "$newer_file" <<'NEWER_CHAT'
# newer-chat

---

### bob — 2026-03-25 10:00

new message
NEWER_CHAT

  run chat list
  [ "$status" -eq 0 ]
  # newer-chat should appear before older-chat in the output
  local newer_pos older_pos
  newer_pos=$(echo "$output" | grep -n "newer-chat" | head -1 | cut -d: -f1)
  older_pos=$(echo "$output" | grep -n "older-chat" | head -1 | cut -d: -f1)
  [ -n "$newer_pos" ] && [ -n "$older_pos" ]
  [ "$newer_pos" -lt "$older_pos" ]
}

# ----- Unread column + --unread filter -----

@test "task list: no Unread column when no identity" {
  send_message "alice" "hello"
  run chat list
  [ "$status" -eq 0 ]
  ! [[ "$output" == *"Unread"* ]]
}

@test "task list --as: shows Unread column" {
  send_message "alice" "hello"
  run chat list --as bob
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unread"* ]]
}

@test "task list --as: Unread reflects messages from other agents" {
  send_message "alice" "one"
  send_message "alice" "two"
  run chat list --as bob --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
for c in channels:
    if c['name'] == 'test-chat':
        assert c['unread'] == 2, f'expected 2 unread, got {c[\"unread\"]}'
        break
else:
    raise SystemExit('test-chat not found')
"
}

@test "task list --as: own messages do not count as unread" {
  send_message "alice" "mine"
  run chat list --as alice --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
for c in channels:
    if c['name'] == 'test-chat':
        assert c['unread'] == 0, f'expected 0 unread (own msgs), got {c[\"unread\"]}'
        break
else:
    raise SystemExit('test-chat not found')
"
}

@test "task list --json: no unread field when no identity" {
  send_message "alice" "hello"
  run chat list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
for c in channels:
    if c['name'] == 'test-chat':
        assert 'unread' not in c, f'unread should be omitted when no identity, got: {c}'
        break
"
}

@test "task list --unread: hides channels with zero unread" {
  # test-chat has no unread for alice (she's the sender)
  send_message "alice" "hi"
  # second channel with unread for alice
  chat_resolve "busy-chat"
  chat_init
  chat_append "bob" "urgent"
  run chat list --as alice --unread
  [ "$status" -eq 0 ]
  [[ "$output" == *"busy-chat"* ]]
  ! [[ "$output" == *"test-chat"* ]]
}

@test "task list --unread: errors without identity" {
  send_message "alice" "hello"
  run chat list --unread
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires an identity"* ]]
}

@test "task list: \$CHAT_IDENTITY env var enables Unread column without --as" {
  # Agents commonly export CHAT_IDENTITY at session start rather than
  # passing --as on every call. Exercise that path explicitly.
  send_message "alice" "hello"
  export CHAT_IDENTITY=bob
  run chat list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['name'] == 'test-chat':
        assert 'unread' in c, 'unread field should appear with CHAT_IDENTITY set'
        assert c['unread'] == 1, f'expected 1 unread, got {c[\"unread\"]}'
        break
else:
    raise SystemExit('test-chat not found')
"
}

@test "task list --unread --all: --unread still filters empty channels" {
  # --all would normally include the empty channel; --unread filters it back out
  # because an empty channel has zero unread by definition.
  send_message "alice" "has-content"
  chat_resolve "empty-chat"
  chat_init
  run chat list --as bob --unread --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-chat"* ]]
  ! [[ "$output" == *"empty-chat"* ]]
}

@test "task list --unread --json: JSON path respects the unread filter" {
  send_message "alice" "hi"
  chat_resolve "quiet-chat"
  chat_init
  chat_append "bob" "seen"
  run chat list --as bob --unread --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
names = sorted(c['name'] for c in channels)
assert names == ['test-chat'], f'expected only test-chat, got: {names}'
assert channels[0]['unread'] == 1
"
}
