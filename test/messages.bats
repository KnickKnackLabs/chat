#!/usr/bin/env bats
# Tests for messages and merge tasks (Python+uv)

load test_helper

# ============================================================================
# Helper: create a second chat channel with messages
# ============================================================================

_setup_second_chat() {
  local name="$1"
  chat_resolve "$name"
  chat_init
  # Restore test-chat as default
  chat_resolve "test-chat"
  chat_init
}

_send_to() {
  local chat="$1" from="$2" msg="$3"
  local old_file="$CHAT_FILE"
  local old_name="$CHAT_NAME"
  chat_resolve "$chat"
  chat_init
  chat_append "$from" "$msg"
  CHAT_FILE="$old_file"
  CHAT_NAME="$old_name"
}

# ============================================================================
# messages task
# ============================================================================

@test "task messages: lists messages in channel" {
  send_message "alice" "hello from alice"
  send_message "bob" "reply from bob"
  run_task messages test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"bob"* ]]
  [[ "$output" == *"2 message(s)"* ]]
}

@test "task messages: --from filters by sender" {
  send_message "alice" "msg from alice"
  send_message "bob" "msg from bob"
  send_message "alice" "another from alice"
  run_task messages test-chat --from alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 message(s)"* ]]
  [[ "$output" == *"alice"* ]]
}

@test "task messages: --last limits count" {
  send_message "alice" "first"
  send_message "bob" "second"
  send_message "carol" "third"
  run_task messages test-chat --last 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 message(s)"* ]]
  [[ "$output" == *"bob"* ]]
  [[ "$output" == *"carol"* ]]
}

@test "task messages: --json outputs valid JSON" {
  send_message "alice" "json test"
  run_task messages test-chat --json
  [ "$status" -eq 0 ]
  # Extract JSON (skip mise's [task] prefix lines on stderr mixed into output)
  local json
  json=$(echo "$output" | sed -n '/^\[$/,$ p')
  echo "$json" | jq '.[0].sender' | grep -q "alice"
  echo "$json" | jq '.[0].timestamp' | grep -q "2026"
  echo "$json" | jq '.[0].body' | grep -q "json test"
}

@test "task messages: --json --id includes message IDs" {
  send_message "alice" "id test"
  run_task messages test-chat --json --id
  [ "$status" -eq 0 ]
  # Extract JSON, then check ID is a 12-char hex string
  local json id
  json=$(echo "$output" | sed -n '/^\[$/,$ p')
  id=$(echo "$json" | jq -r '.[0].id')
  [ ${#id} -eq 12 ]
}

@test "task messages: empty channel shows no messages" {
  run_task messages test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"No messages"* ]]
}

@test "task messages: nonexistent channel fails" {
  run_task messages nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

# ============================================================================
# merge task
# ============================================================================

@test "task merge: dry-run shows plan without modifying files" {
  send_message "alice" "in test-chat"
  _send_to "other-chat" "bob" "in other-chat"
  run_task merge other-chat test-chat --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]]
  [[ "$output" == *"2 messages"* ]]
  # Files should still exist unchanged
  [ -f "$CHAT_DATA_DIR/other-chat.md" ]
  [ -f "$CHAT_DATA_DIR/test-chat.md" ]
}

@test "task merge: merges source into target" {
  send_message "alice" "target msg"
  _send_to "source-chat" "bob" "source msg"
  run_task merge source-chat test-chat
  [ "$status" -eq 0 ]
  # Source file should be removed
  [ ! -f "$CHAT_DATA_DIR/source-chat.md" ]
  # Target should contain both messages
  grep -q "alice" "$CHAT_FILE"
  grep -q "bob" "$CHAT_FILE"
}

@test "task merge: messages are tagged with source channel" {
  send_message "alice" "target msg"
  _send_to "old-chat" "bob" "old msg"
  run_task merge old-chat test-chat
  [ "$status" -eq 0 ]
  # Source tags should appear in merged file
  grep -q "old-chat" "$CHAT_FILE"
}

@test "task merge: --no-tag omits source annotations" {
  send_message "alice" "target msg"
  _send_to "old-chat" "bob" "old msg"
  run_task merge old-chat test-chat --no-tag
  [ "$status" -eq 0 ]
  # The Unicode arrow tag should not appear
  ! grep -q "⟵" "$CHAT_FILE"
}

@test "task merge: fails if source doesn't exist" {
  run_task merge nonexistent test-chat
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "task merge: fails if source equals target" {
  run_task merge test-chat test-chat
  [ "$status" -ne 0 ]
  [[ "$output" == *"same channel"* ]]
}

@test "task merge: cursors are reset after merge" {
  send_message "alice" "msg"
  mark_read "alice"
  _send_to "other-chat" "bob" "other msg"
  # Set cursor on other-chat too
  chat_resolve "other-chat"
  chat_set_cursor "alice"
  chat_resolve "test-chat"

  run_task merge other-chat test-chat
  [ "$status" -eq 0 ]
  # Cursor should be reset to 0
  local cursor
  cursor=$(cat "$CHAT_DATA_DIR/.cursors/test-chat/alice")
  [ "$cursor" = "0" ]
}

@test "task merge: source cursor dir is cleaned up" {
  _send_to "other-chat" "bob" "msg"
  chat_resolve "other-chat"
  chat_set_cursor "bob"
  chat_resolve "test-chat"
  send_message "alice" "target"

  run_task merge other-chat test-chat
  [ "$status" -eq 0 ]
  [ ! -d "$CHAT_DATA_DIR/.cursors/other-chat" ]
}
