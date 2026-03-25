#!/usr/bin/env bats
# Task-level integration tests — exercise actual task scripts via chat() shim
#
# API v2: --as replaces --for/--from, implicit identity via $CHAT_IDENTITY,
# read absorbs check/log/messages, welcome renamed to status.

load test_helper

# ============================================================================
# read task
# ============================================================================

@test "task read: no new messages exits 0" {
  mark_read "alice"
  run chat read --as alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"No new messages"* ]]
}

@test "task read: shows unread messages" {
  mark_read "alice"
  send_message "bob" "hey alice"
  run chat read --as alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"hey alice"* ]]
}

@test "task read: advances cursor after reading" {
  mark_read "alice"
  send_message "bob" "msg1"
  run chat read --as alice --chat test-chat
  [ "$status" -eq 0 ]

  # Second read should show no new messages
  run chat read --as alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"No new messages"* ]]
}

@test "task read: --peek does not advance cursor" {
  mark_read "alice"
  send_message "bob" "peeked"
  local cursor_before
  cursor_before=$(chat_get_cursor "alice")

  run chat read --as alice --chat test-chat --peek
  [ "$status" -eq 0 ]
  [[ "$output" == *"peeked"* ]]

  local cursor_after
  cursor_after=$(chat_get_cursor "alice")
  [ "$cursor_before" = "$cursor_after" ]
}

@test "task read: --all shows everything" {
  send_message "bob" "visible"
  mark_read "alice"
  send_message "carol" "also visible"
  run chat read --as alice --chat test-chat --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"visible"* ]]
  [[ "$output" == *"also visible"* ]]
}

@test "task read: without --as uses spectator mode (shows all)" {
  send_message "bob" "hello"
  run chat read --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
}

@test "task read: CHAT_IDENTITY env var used when --as omitted" {
  mark_read "alice"
  send_message "bob" "env-identity test"
  run env CHAT_IDENTITY="alice" chat read --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"env-identity test"* ]]
}

@test "task read: --from filters by sender" {
  mark_read "alice"
  send_message "bob" "from bob"
  send_message "carol" "from carol"
  run chat read --as alice --chat test-chat --from bob
  [ "$status" -eq 0 ]
  [[ "$output" == *"from bob"* ]]
  [[ "$output" != *"from carol"* ]]
}

@test "task read: --all --last shows last N messages" {
  send_message "alice" "first"
  send_message "bob" "second"
  send_message "carol" "third"
  run chat read --chat test-chat --all --last 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"third"* ]]
  [[ "$output" != *"first"* ]]
}

@test "task read: --last implies --all (shows past cursor)" {
  send_message "alice" "old"
  send_message "bob" "also old"
  mark_read "carol"
  send_message "alice" "new"
  # carol's cursor is past "old" and "also old", but --last 3 should show all 3
  run chat read --as carol --chat test-chat --last 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"old"* ]]
  [[ "$output" == *"also old"* ]]
  [[ "$output" == *"new"* ]]
}

@test "task read: --from implies --all (shows past cursor)" {
  send_message "alice" "before cursor"
  mark_read "bob"
  send_message "alice" "after cursor"
  # bob's cursor is past "before cursor", but --from alice should show both
  run chat read --as bob --chat test-chat --from alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"before cursor"* ]]
  [[ "$output" == *"after cursor"* ]]
}

@test "task read: cursor advances after reading messages" {
  send_message "bob" "setup"
  mark_read "alice"

  local cursor_before
  cursor_before=$(chat_get_cursor "alice")

  send_message "bob" "new"
  run chat read --as alice --chat test-chat
  [ "$status" -eq 0 ]

  local cursor_after
  cursor_after=$(chat_get_cursor "alice")
  [ "$cursor_after" -gt "$cursor_before" ]
}

# ============================================================================
# send task
# ============================================================================

@test "task send: appends message" {
  run chat send --as alice --chat test-chat "hello world"
  [ "$status" -eq 0 ]
  grep -q "hello world" "$CHAT_FILE"
}

@test "task send: message has sender header" {
  run chat send --as alice --chat test-chat "test"
  [ "$status" -eq 0 ]
  grep -q "^### alice" "$CHAT_FILE"
}

@test "task send: confirms with output" {
  run chat send --as alice --chat test-chat "hi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sent to test-chat"* ]]
}

@test "task send: CHAT_IDENTITY env var used when --as omitted" {
  run env CHAT_IDENTITY="alice" chat send --chat test-chat "env identity send"
  [ "$status" -eq 0 ]
  grep -q "### alice" "$CHAT_FILE"
  grep -q "env identity send" "$CHAT_FILE"
}

@test "task send: fails without identity" {
  unset CHAT_IDENTITY
  run chat send --chat test-chat "no identity"
  [ "$status" -ne 0 ]
  [[ "$output" == *"identity required"* ]]
}

@test "task send: rejects empty message" {
  run chat send --as alice --chat test-chat ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty"* ]]
}

@test "task send: rejects message over 10 lines" {
  local long_msg
  long_msg=$(printf 'line %s\n' $(seq 1 11))
  run chat send --as alice --chat test-chat "$long_msg"
  [ "$status" -ne 0 ]
  [[ "$output" == *"too long"* ]]
}

@test "task send: allows message at exactly 10 lines" {
  local msg
  msg=$(printf 'line %s\n' $(seq 1 10))
  run chat send --as alice --chat test-chat "$msg"
  [ "$status" -eq 0 ]
}

@test "task send: guard blocks send when unread messages exist" {
  # alice sends first message (cursor stays 0 — new agent, guard skips)
  run chat send --as alice --chat test-chat "first"
  [ "$status" -eq 0 ]

  # alice reads to set cursor > 0
  mark_read "alice"

  # bob sends a message alice hasn't read
  send_message "bob" "unread msg"

  # alice tries to send — guard should block
  run chat send --as alice --chat test-chat "blocked"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unread"* ]]
}

@test "task send: --force bypasses unread guard" {
  run chat send --as alice --chat test-chat "first"
  [ "$status" -eq 0 ]
  mark_read "alice"
  send_message "bob" "unread"

  run chat send --as alice --chat test-chat "forced" --force
  [ "$status" -eq 0 ]
  grep -q "forced" "$CHAT_FILE"
}

@test "task send: new agent (cursor=0) bypasses guard" {
  # bob has never read — cursor is 0
  send_message "carol" "some message"
  # bob should be able to send despite carol's unread message
  run chat send --as bob --chat test-chat "hi from bob"
  [ "$status" -eq 0 ]
}

@test "task send: new agent can send multiple times without reading (cursor=0)" {
  # alice has never read — cursor stays at 0, guard is skipped
  run chat send --as alice --chat test-chat "first msg"
  [ "$status" -eq 0 ]

  # alice sends again — still cursor=0, guard still skipped
  run chat send --as alice --chat test-chat "second msg"
  [ "$status" -eq 0 ]
  grep -q "second msg" "$CHAT_FILE"
}

@test "task send: own unread messages do not trigger guard" {
  # alice sends and reads to set cursor > 0
  send_message "alice" "setup"
  mark_read "alice"

  # alice sends — her own message is now "unread" (cursor didn't advance)
  run chat send --as alice --chat test-chat "first from alice"
  [ "$status" -eq 0 ]

  # alice sends again — guard should NOT block (only own messages are unread)
  run chat send --as alice --chat test-chat "second from alice"
  [ "$status" -eq 0 ]
  grep -q "second from alice" "$CHAT_FILE"
}

@test "task send: does not advance sender cursor" {
  # alice sends, then reads (cursor > 0)
  send_message "alice" "setup"
  mark_read "alice"

  # bob sends a message alice hasn't read
  send_message "bob" "hey alice"

  # alice sends with --force to bypass the guard
  run chat send --as alice --chat test-chat --force "replying without reading"
  [ "$status" -eq 0 ]

  # alice's cursor should NOT have advanced — bob's message is still unread
  run chat read --as alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"hey alice"* ]]
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

### alice — 2025-01-01 10:00

old message
EOF

  cat > "$newer_file" <<'EOF'
# newer-chat

---

### bob — 2026-03-25 10:00

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

# ============================================================================
# status task (replaces welcome)
# ============================================================================

@test "task status: shows chat name" {
  run chat status --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-chat"* ]]
}

@test "task status: shows unread count with --as" {
  send_message "bob" "hey"
  run chat status --as alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"unread"* ]]
}

@test "task status: shows no unread when fully read" {
  mark_read "alice"
  run chat status --as alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"No unread"* ]]
}

@test "task status --json: outputs valid JSON" {
  send_message "alice" "hello"
  run chat status --as bob --chat test-chat --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)"
}

@test "task status --json: includes unread count with --as" {
  send_message "alice" "msg1"
  send_message "alice" "msg2"
  run chat status --as bob --chat test-chat --json
  [ "$status" -eq 0 ]
  local unread
  unread=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['unread'])")
  [ "$unread" = "2" ]
}

@test "task status --json: unread is 0 when fully read" {
  send_message "alice" "hello"
  mark_read "bob"
  run chat status --as bob --chat test-chat --json
  [ "$status" -eq 0 ]
  local unread
  unread=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['unread'])")
  [ "$unread" = "0" ]
}

@test "task status --json: omits unread when no --as" {
  send_message "alice" "hello"
  unset CHAT_IDENTITY
  run chat status --chat test-chat --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert 'unread' not in data, f'unread should not be present without --as, got: {data}'
"
}

@test "task status --json: no human-readable header in output" {
  send_message "alice" "hello"
  run chat status --as alice --chat test-chat --json
  [ "$status" -eq 0 ]
  # First non-empty char should be '{' (JSON object)
  local first_char
  first_char=$(echo "$output" | head -c 1)
  [ "$first_char" = "{" ]
}

# ============================================================================
# cursor:clear task
# ============================================================================

@test "task cursor:clear: resets cursor to 0" {
  send_message "alice" "msg"
  mark_read "bob"
  local cursor
  cursor=$(chat_get_cursor "bob")
  [ "$cursor" -gt 0 ]

  run chat cursor:clear --as bob --chat test-chat
  [ "$status" -eq 0 ]

  cursor=$(chat_get_cursor "bob")
  [ "$cursor" = "0" ]
}

@test "task cursor:clear: messages appear as unread after clear" {
  send_message "alice" "hello"
  mark_read "bob"

  # bob has no unread
  local count
  count=$(chat_count_new "bob")
  [ "$count" = "0" ]

  run chat cursor:clear --as bob --chat test-chat
  [ "$status" -eq 0 ]

  # Now bob should see the message as unread
  count=$(chat_count_new "bob")
  [ "$count" -gt 0 ]
}

@test "task cursor:clear: no-op when cursor doesn't exist" {
  run chat cursor:clear --as newagent --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"already at start"* ]]
}

@test "task cursor:clear: requires identity" {
  unset CHAT_IDENTITY
  run chat cursor:clear --chat test-chat
  [ "$status" -ne 0 ]
  [[ "$output" == *"identity required"* ]]
}

# ============================================================================
# non-existent channel — read-only commands should fail, send should create
# ============================================================================

@test "task read: fails on non-existent channel" {
  run chat read --chat no-such-channel
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task read: does not create file for non-existent channel" {
  run chat read --chat no-such-channel
  [ ! -f "$CHAT_DATA_DIR/no-such-channel.md" ]
}

@test "task status: fails on non-existent channel" {
  run chat status --chat no-such-channel
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task wait: fails on non-existent channel" {
  run chat wait --chat no-such-channel --timeout 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task clear: fails on non-existent channel" {
  run chat clear --chat no-such-channel --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task cursor:clear: fails on non-existent channel" {
  run chat cursor:clear --as alice --chat no-such-channel
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task send: creates channel that did not exist" {
  run chat send --as alice --chat brand-new-channel "first message"
  [ "$status" -eq 0 ]
  [ -f "$CHAT_DATA_DIR/brand-new-channel.md" ]
  grep -q "first message" "$CHAT_DATA_DIR/brand-new-channel.md"
}

# ============================================================================
# remove task
# ============================================================================

@test "task remove: deletes channel file and cursor dir" {
  send_message "alice" "hello"
  mark_read "alice"
  [ -f "$CHAT_FILE" ]
  [ -d "$CHAT_CURSOR_DIR" ]

  run chat remove --chat test-chat --yes
  [ "$status" -eq 0 ]
  [ ! -f "$CHAT_FILE" ]
  [ ! -d "$CHAT_CURSOR_DIR" ]
  [[ "$output" == *"Removed"* ]]
}

@test "task remove: fails on non-existent channel" {
  run chat remove --chat no-such-channel --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task remove: refuses to remove global channel" {
  # Create the global channel
  chat_resolve "global"
  chat_init
  run chat remove --chat global --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot remove the global channel"* ]]
  # File should still exist
  [ -f "$CHAT_DATA_DIR/global.md" ]
}

@test "task remove: channel no longer appears in list" {
  send_message "alice" "hello"
  run chat list --json
  echo "$output" | python3 -c "
import json, sys
names = [c['name'] for c in json.load(sys.stdin)]
assert 'test-chat' in names, f'expected test-chat in {names}'
"

  run chat remove --chat test-chat --yes
  [ "$status" -eq 0 ]

  run chat list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
names = [c['name'] for c in json.load(sys.stdin)]
assert 'test-chat' not in names, f'test-chat should be gone, got {names}'
"
}
