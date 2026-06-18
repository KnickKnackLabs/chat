#!/usr/bin/env bats
# List, status, and unread task integration tests

load test_helper
# ============================================================================
# export task
# ============================================================================

@test "task export: stdout markdown exports raw channel file" {
  send_message "alice" "hello"
  run chat export test-chat --stdout
  [ "$status" -eq 0 ]
  [[ "$output" == *"# test-chat"* ]]
  [[ "$output" == *"from: alice"* ]]
  [[ "$output" == *"hello"* ]]
}

@test "task export: stdout json exports structured messages" {
  send_message "alice" "hello"
  run chat export test-chat --stdout --format json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert data[0]['sender'] == 'alice'
assert data[0]['body'] == 'hello'
"
}

@test "task export: filtered markdown stays markdown" {
  send_message "alice" "hello"
  run chat export test-chat --stdout --after 1970-01-01
  [ "$status" -eq 0 ]
  [[ "$output" == *"# test-chat"* ]]
  [[ "$output" == *"from: alice"* ]]
  [[ "$output" == *"hello"* ]]
}

@test "task export: rejects invalid format" {
  run chat export test-chat --stdout --format xml
  [ "$status" -ne 0 ]
  [[ "$output" == *"--format must be md or json"* ]]
}

@test "task export: README documents flags when default precedes help" {
  grep -q 'chat export \[--format <format>\].*\[chat\]' "$CHAT_REPO_ROOT/README.md"
  grep -q '| `--format` | Export format: md or json.*| `md`' "$CHAT_REPO_ROOT/README.md"
  grep -q '| `--stdout` | Print to stdout instead of uploading' "$CHAT_REPO_ROOT/README.md"
}

@test "task export: upload requires blob env" {
  send_message "alice" "hello"
  run chat export test-chat
  [ "$status" -ne 0 ]
  [[ "$output" == *"B2_ALIAS and B2_BUCKET must be set"* ]]
  [[ "$output" == *"--stdout"* ]]
}

@test "task export: upload delegates to blobs put" {
  send_message "alice" "hello"
  _setup_mock_blobs
  export B2_ALIAS=test
  export B2_BUCKET=test-bucket

  run chat export test-chat --key chat/test-chat/manual.md
  [ "$status" -eq 0 ]
  [[ "$output" == "chat/test-chat/manual.md" ]]
  grep -q "put chat/test-chat/manual.md -" "$BLOBS_LOG"
  grep -q "hello" "$BLOBS_STDIN"
}

# ============================================================================
# list task
# ============================================================================

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

  cat > "$older_file" <<'EOF'
# older-chat

---

---
id: 1
from: alice
ts: 2025-01-01 10:00
---
old message
EOF

  cat > "$newer_file" <<'EOF'
# newer-chat

---

---
id: 1
from: bob
ts: 2026-03-25 10:00
---
new message
EOF

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

# ============================================================================
# status task (replaces welcome)
# ============================================================================

@test "task status: shows chat name" {
  run chat status test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-chat"* ]]
}

@test "task status: shows unread count with --as" {
  send_message "bob" "hey"
  run chat status test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unread"* ]]
}

@test "task status: hides unread row when fully read" {
  mark_read "alice"
  run chat status test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" != *"Unread"* ]]
}

@test "task status --json: outputs valid JSON" {
  send_message "alice" "hello"
  run chat status test-chat --as bob --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)"
}

@test "task status --json: includes unread count with --as" {
  send_message "alice" "msg1"
  send_message "alice" "msg2"
  run chat status test-chat --as bob --json
  [ "$status" -eq 0 ]
  local unread
  unread=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['unread'])")
  [ "$unread" = "2" ]
}

@test "task status --json: unread is 0 when fully read" {
  send_message "alice" "hello"
  mark_read "bob"
  run chat status test-chat --as bob --json
  [ "$status" -eq 0 ]
  local unread
  unread=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['unread'])")
  [ "$unread" = "0" ]
}

@test "task status --json: omits unread when no --as" {
  send_message "alice" "hello"
  unset CHAT_IDENTITY
  run chat status test-chat --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert 'unread' not in data, f'unread should not be present without --as, got: {data}'
"
}

@test "task status --json: no human-readable header in output" {
  send_message "alice" "hello"
  run chat status test-chat --as alice --json
  [ "$status" -eq 0 ]
  # First non-empty char should be '{' (JSON object)
  local first_char
  first_char=$(echo "$output" | head -c 1)
  [ "$first_char" = "{" ]
}

# ============================================================================
# unread task
# ============================================================================

@test "task unread: zero total exits 0 with no output" {
  mark_read "alice"
  run chat unread --as alice
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "task unread: zero total JSON returns structured response" {
  mark_read "alice"
  run chat unread --as alice --json
  [ "$status" -eq 0 ]
  total=$(echo "$output" | jq '.total')
  [ "$total" -eq 0 ]
  channels=$(echo "$output" | jq '.channels | length')
  [ "$channels" -eq 0 ]
}

@test "task unread: sums across channels" {
  # Create a second channel
  CHAT_NAME="other-chat"
  CHAT_FILE="$CHAT_DATA_DIR/other-chat.md"
  CHAT_CURSOR_DIR="$CHAT_DATA_DIR/.cursors/other-chat"
  chat_init

  # Mark both as read, then send messages
  chat_resolve "test-chat"
  mark_read "alice"
  send_message "bob" "msg1"
  send_message "bob" "msg2"

  chat_resolve "other-chat"
  mark_read "alice"
  send_message "carol" "msg3"

  run chat unread --as alice
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "task unread: excludes own messages" {
  mark_read "alice"
  send_message "alice" "my own message"
  send_message "bob" "from bob"
  run chat unread --as alice
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "task unread: JSON shows per-channel breakdown" {
  # Create a second channel
  CHAT_NAME="other-chat"
  CHAT_FILE="$CHAT_DATA_DIR/other-chat.md"
  CHAT_CURSOR_DIR="$CHAT_DATA_DIR/.cursors/other-chat"
  chat_init

  chat_resolve "test-chat"
  mark_read "alice"
  send_message "bob" "msg1"

  chat_resolve "other-chat"
  mark_read "alice"
  send_message "carol" "msg2"
  send_message "carol" "msg3"

  run chat unread --as alice --json
  [ "$status" -eq 0 ]
  total=$(echo "$output" | jq '.total')
  [ "$total" -eq 3 ]
  test_count=$(echo "$output" | jq '.channels["test-chat"]')
  [ "$test_count" -eq 1 ]
  other_count=$(echo "$output" | jq '.channels["other-chat"]')
  [ "$other_count" -eq 2 ]
}

@test "task unread: no channels exits 0" {
  # Remove all chat files
  rm -f "$CHAT_DATA_DIR"/*.md
  run chat unread --as alice
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
