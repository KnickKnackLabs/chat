#!/usr/bin/env bats
bats_require_minimum_version 1.10.0
# Unit tests for lib/chat.sh core functions

load test_helper

# ============================================================================
# chat_init
# ============================================================================

@test "init: creates chat file" {
  [ -f "$CHAT_FILE" ]
}

@test "init: creates cursor directory" {
  [ -d "$CHAT_CURSOR_DIR" ]
}

@test "init: chat file has header" {
  head -1 "$CHAT_FILE" | grep -q "^# test-chat"
}

@test "init: idempotent — second call doesn't duplicate" {
  local before
  before=$(wc -l < "$CHAT_FILE" | tr -d ' ')
  chat_init
  local after
  after=$(wc -l < "$CHAT_FILE" | tr -d ' ')
  [ "$before" = "$after" ]
}

# ============================================================================
# chat_line_count
# ============================================================================

@test "line_count: returns correct count" {
  local count
  count=$(chat_line_count)
  local expected
  expected=$(wc -l < "$CHAT_FILE" | tr -d ' ')
  [ "$count" = "$expected" ]
}

# ============================================================================
# cursor: get/set
# ============================================================================

@test "cursor: default is 0 for new agent" {
  local cursor
  cursor=$(chat_get_cursor "alice")
  [ "$cursor" = "0" ]
}

@test "cursor: set and get round-trips" {
  chat_set_cursor "alice"
  local cursor
  cursor=$(chat_get_cursor "alice")
  local total
  total=$(chat_line_count)
  [ "$cursor" = "$total" ]
}

@test "cursor: agents have independent cursors" {
  send_message "bob" "first message"
  chat_set_cursor "alice"

  send_message "bob" "second message"
  chat_set_cursor "bob"

  local alice_cursor bob_cursor
  alice_cursor=$(chat_get_cursor "alice")
  bob_cursor=$(chat_get_cursor "bob")
  [ "$alice_cursor" -lt "$bob_cursor" ]
}

@test "cursor: set requires agent name" {
  run chat_set_cursor ""
  [ "$status" -ne 0 ]
}

@test "cursor: set saves .prev when cursor already exists" {
  send_message "bob" "first"
  chat_set_cursor "alice"
  local first_pos
  first_pos=$(chat_get_cursor "alice")

  send_message "bob" "second"
  chat_set_cursor "alice"

  local prev_file="$CHAT_CURSOR_DIR/alice.prev"
  [ -f "$prev_file" ]
  [ "$(cat "$prev_file")" = "$first_pos" ]
}

@test "cursor: set does not create .prev on first advance" {
  chat_set_cursor "alice"
  [ ! -f "$CHAT_CURSOR_DIR/alice.prev" ]
}

@test "cursor: set preserves .prev when cursor does not advance" {
  send_message "bob" "first"
  chat_set_cursor "alice"
  local first_pos
  first_pos=$(chat_get_cursor "alice")

  send_message "bob" "second"
  chat_set_cursor "alice"

  chat_set_cursor "alice"

  local prev_file="$CHAT_CURSOR_DIR/alice.prev"
  [ -f "$prev_file" ]
  [ "$(cat "$prev_file")" = "$first_pos" ]
}

