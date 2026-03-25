#!/usr/bin/env bats
# Tests for read --json (advanced query) and merge task (Python+uv)

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
# read --json (absorbs messages task)
# ============================================================================

@test "task read --json: outputs valid JSON" {
  send_message "alice" "json test"
  run chat read --chat test-chat --all --json
  [ "$status" -eq 0 ]
  local json
  json=$(echo "$output" | sed -n '/^\[$/,$ p')
  echo "$json" | jq '.[0].sender' | grep -q "alice"
  echo "$json" | jq '.[0].body' | grep -q "json test"
}

@test "task read --json: --from filters by sender" {
  send_message "alice" "msg from alice"
  send_message "bob" "msg from bob"
  run chat read --chat test-chat --all --json --from alice
  [ "$status" -eq 0 ]
  local json
  json=$(echo "$output" | sed -n '/^\[$/,$ p')
  local count
  count=$(echo "$json" | jq 'length')
  [ "$count" -eq 1 ]
  echo "$json" | jq '.[0].sender' | grep -q "alice"
}

@test "task read --json --id: includes message IDs" {
  send_message "alice" "id test"
  run chat read --chat test-chat --all --json --id
  [ "$status" -eq 0 ]
  local json id
  json=$(echo "$output" | sed -n '/^\[$/,$ p')
  id=$(echo "$json" | jq -r '.[0].id')
  [ ${#id} -eq 12 ]
}

@test "task read --json: empty channel outputs empty array" {
  run chat read --chat test-chat --all --json
  [ "$status" -eq 0 ]
  [[ "$output" == *"[]"* ]]
}

# ============================================================================
# merge task
# ============================================================================

@test "task merge: dry-run shows plan without modifying files" {
  send_message "alice" "in test-chat"
  _send_to "other-chat" "bob" "in other-chat"
  run chat merge other-chat test-chat --dry-run
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
  run chat merge source-chat test-chat
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
  run chat merge old-chat test-chat
  [ "$status" -eq 0 ]
  # Source tags should appear in merged file
  grep -q "old-chat" "$CHAT_FILE"
}

@test "task merge: --no-tag omits source annotations" {
  send_message "alice" "target msg"
  _send_to "old-chat" "bob" "old msg"
  run chat merge old-chat test-chat --no-tag
  [ "$status" -eq 0 ]
  # The Unicode arrow tag should not appear
  ! grep -q "⟵" "$CHAT_FILE"
}

@test "task merge: fails if source doesn't exist" {
  run chat merge nonexistent test-chat
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "task merge: fails if source equals target" {
  run chat merge test-chat test-chat
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

  run chat merge other-chat test-chat
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

  run chat merge other-chat test-chat
  [ "$status" -eq 0 ]
  [ ! -d "$CHAT_DATA_DIR/.cursors/other-chat" ]
}
