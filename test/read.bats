#!/usr/bin/env bats
# Integration tests for read behavior

load test_helper

# ============================================================================
# Basic read flow
# ============================================================================

@test "read: new_messages returns content for unread" {
  send_message "bob" "hello alice"
  # alice hasn't read yet — cursor is 0, but chat_new_messages uses cursor
  # With cursor=0, tail -n +1 returns everything
  mark_read "alice"  # set baseline
  send_message "bob" "new message for alice"
  run chat_new_messages "alice"
  [ "$status" -eq 0 ]
  [[ "$output" == *"new message for alice"* ]]
}

@test "read: no new messages returns failure" {
  mark_read "alice"
  run chat_new_messages "alice"
  [ "$status" -eq 1 ]
}

@test "read: cursor advances after set_cursor" {
  send_message "bob" "msg1"
  mark_read "alice"
  local cursor_after
  cursor_after=$(chat_get_cursor "alice")

  send_message "bob" "msg2"
  run chat_new_messages "alice"
  [[ "$output" == *"msg2"* ]]
  # msg1 should not be in new messages
  [[ "$output" != *"msg1"* ]]
}

# ============================================================================
# Multiple readers
# ============================================================================

@test "read: alice and bob have independent views" {
  send_message "carol" "msg for everyone"
  mark_read "alice"

  send_message "carol" "msg2"

  # alice: only sees msg2
  run chat_new_messages "alice"
  [[ "$output" == *"msg2"* ]]
  [[ "$output" != *"msg for everyone"* ]]

  # bob: cursor still at 0, sees everything from line 1
  local bob_cursor
  bob_cursor=$(chat_get_cursor "bob")
  [ "$bob_cursor" = "0" ]
}

# ============================================================================
# count_new accuracy
# ============================================================================

@test "read: count matches actual message blocks" {
  mark_read "alice"
  send_message "bob" "one"
  send_message "carol" "two"
  local count
  count=$(chat_count_new "alice")
  [ "$count" = "2" ]
}

@test "read: count is 0 after reading" {
  send_message "bob" "hello"
  mark_read "alice"
  local count
  count=$(chat_count_new "alice")
  [ "$count" = "0" ]
}

# ============================================================================
# Edge cases
# ============================================================================

@test "read: cursor beyond file length resets gracefully" {
  # Manually set cursor beyond file length
  printf '99999' > "$CHAT_CURSOR_DIR/alice"
  local cursor
  cursor=$(chat_get_cursor "alice")
  local total
  total=$(chat_line_count)
  # cursor > total — new_messages should return nothing (cursor >= total)
  run chat_new_messages "alice"
  [ "$status" -eq 1 ]
}

@test "read: works with empty message bodies" {
  mark_read "alice"
  send_message "bob" ""
  local count
  count=$(chat_count_new "alice")
  [ "$count" = "1" ]
}
