#!/usr/bin/env bats
# Cursor and channel management task integration tests

load test_helper
# ============================================================================
# cursor:clear task
# ============================================================================

@test "task cursor:clear: resets cursor to 0" {
  send_message "alice" "msg"
  mark_read "bob"
  local cursor
  cursor=$(chat_get_cursor "bob")
  [ "$cursor" -gt 0 ]

  run chat cursor:clear test-chat --as bob
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

  run chat cursor:clear test-chat --as bob
  [ "$status" -eq 0 ]

  # Now bob should see the message as unread
  count=$(chat_count_new "bob")
  [ "$count" -gt 0 ]
}

@test "task cursor:clear: no-op when cursor doesn't exist" {
  run chat cursor:clear test-chat --as newagent
  [ "$status" -eq 0 ]
  [[ "$output" == *"already at start"* ]]
}

@test "task cursor:clear: requires identity" {
  unset CHAT_IDENTITY
  run chat cursor:clear test-chat
  [ "$status" -ne 0 ]
  [[ "$output" == *"identity required"* ]]
}

@test "task cursor:clear: clears inherited usage env for omitted chat and identity" {
  export CHAT_CHANNEL="test-chat"
  export CHAT_IDENTITY="alice"
  export usage_chat="no-such-channel"
  export usage_as="mallory"

  send_message "bob" "msg"
  mark_read "alice"

  run chat cursor:clear
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cursor cleared for alice on test-chat"* ]]
  [ "$(chat_get_cursor "alice")" = "0" ]
}

# ============================================================================
# cursor:undo task
# ============================================================================

@test "task cursor:undo: restores cursor to pre-read position" {
  send_message "bob" "msg1"
  mark_read "alice"
  local cursor_before
  cursor_before=$(chat_get_cursor "alice")

  send_message "bob" "msg2"
  run chat read test-chat --as alice
  [ "$status" -eq 0 ]

  run chat cursor:undo test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cursor restored"* ]]

  local cursor_after
  cursor_after=$(chat_get_cursor "alice")
  [ "$cursor_after" = "$cursor_before" ]
}

@test "task cursor:undo: second read after undo shows same messages" {
  mark_read "alice"
  send_message "bob" "hello again"

  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello again"* ]]

  run chat cursor:undo test-chat --as alice
  [ "$status" -eq 0 ]

  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello again"* ]]
}

@test "task cursor:undo: no-op when no prior read" {
  run chat cursor:undo test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to undo"* ]]
}

@test "task cursor:undo: no-op after read --peek" {
  mark_read "alice"
  send_message "bob" "peeked"

  run chat read test-chat --as alice --peek
  [ "$status" -eq 0 ]

  run chat cursor:undo test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to undo"* ]]
}

@test "task cursor:undo: no-op read does not clobber previous position" {
  mark_read "alice"
  send_message "bob" "recover me"

  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"recover me"* ]]

  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"No new messages"* ]]

  run chat cursor:undo test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cursor restored"* ]]

  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"recover me"* ]]
}

@test "task cursor:undo: second undo is a no-op (one level only)" {
  send_message "bob" "msg"
  mark_read "alice"
  send_message "bob" "msg2"

  run chat read test-chat --as alice
  [ "$status" -eq 0 ]

  run chat cursor:undo test-chat --as alice
  [ "$status" -eq 0 ]

  run chat cursor:undo test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to undo"* ]]
}

@test "task cursor:undo: no-op after cursor:clear" {
  send_message "bob" "msg"
  mark_read "alice"
  send_message "bob" "msg2"

  run chat read test-chat --as alice
  [ "$status" -eq 0 ]

  run chat cursor:clear test-chat --as alice
  [ "$status" -eq 0 ]

  run chat cursor:undo test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to undo"* ]]
}

@test "task cursor:undo: requires identity" {
  unset CHAT_IDENTITY
  run chat cursor:undo test-chat
  [ "$status" -ne 0 ]
  [[ "$output" == *"identity required"* ]]
}

@test "task cursor:undo: clears inherited usage env for omitted chat and identity" {
  export CHAT_CHANNEL="test-chat"
  export CHAT_IDENTITY="alice"
  export usage_chat="no-such-channel"
  export usage_as="mallory"

  mark_read "alice"
  send_message "bob" "recover via env"

  run chat read
  [ "$status" -eq 0 ]
  [[ "$output" == *"recover via env"* ]]

  run chat cursor:undo
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cursor restored for alice on test-chat"* ]]
}

@test "task cursor:undo: help examples use the actual task name" {
  run chat cursor:undo --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"chat cursor:undo --as alice"* ]]
  [[ "$output" != *"chat cursor undo"* ]]
}

# ============================================================================
# non-existent channel — read-only commands should fail, send should create
# ============================================================================

@test "task read: fails on non-existent channel" {
  run chat read no-such-channel
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task read: does not create file for non-existent channel" {
  run chat read no-such-channel
  [ ! -f "$CHAT_DATA_DIR/no-such-channel.md" ]
}

@test "task status: fails on non-existent channel" {
  run chat status no-such-channel
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task wait: fails on non-existent channel" {
  run chat wait no-such-channel --timeout 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task clear: fails on non-existent channel" {
  run chat clear no-such-channel --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task cursor:clear: fails on non-existent channel" {
  run chat cursor:clear no-such-channel --as alice
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task cursor:undo: fails on non-existent channel" {
  run chat cursor:undo no-such-channel --as alice
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task cursor:clear: help examples use the actual task name" {
  run chat cursor:clear --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"chat cursor:clear --as alice"* ]]
  [[ "$output" != *"chat cursor clear"* ]]
}

@test "task send: creates channel that did not exist" {
  run chat send --as alice --chat brand-new-channel --msg "first message"
  [ "$status" -eq 0 ]
  [ -f "$CHAT_DATA_DIR/brand-new-channel.md" ]
  grep -q "first message" "$CHAT_DATA_DIR/brand-new-channel.md"
}

@test "task send: invalid existing chat file format fails closed" {
  cat > "$CHAT_FILE" <<'BAD'
# malformed

Shared communication channel.

---
not a frontmatter message block
BAD
  local before
  before=$(cat "$CHAT_FILE")

  run chat send --as alice --chat test-chat --msg "should not append"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid chat file format"* ]]
  [ "$(cat "$CHAT_FILE")" = "$before" ]
}

# ============================================================================
# remove task
# ============================================================================

@test "task remove: deletes channel file and cursor dir" {
  send_message "alice" "hello"
  mark_read "alice"
  [ -f "$CHAT_FILE" ]
  [ -d "$CHAT_CURSOR_DIR" ]

  run chat remove test-chat --yes
  [ "$status" -eq 0 ]
  [ ! -f "$CHAT_FILE" ]
  [ ! -d "$CHAT_CURSOR_DIR" ]
  [[ "$output" == *"Removed"* ]]
}

@test "task remove: fails on non-existent channel" {
  run chat remove no-such-channel --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task remove: refuses to remove default channel" {
  chat_resolve "default"
  chat_init
  run chat remove default --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot remove the default channel"* ]]
  [ -f "$CHAT_DATA_DIR/default.md" ]
}

@test "task remove: refuses to remove legacy global channel" {
  chat_resolve "global"
  chat_init
  run chat remove global --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot remove the global channel"* ]]
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

  run chat remove test-chat --yes
  [ "$status" -eq 0 ]

  run chat list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
names = [c['name'] for c in json.load(sys.stdin)]
assert 'test-chat' not in names, f'test-chat should be gone, got {names}'
"
}

