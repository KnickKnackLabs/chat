#!/usr/bin/env bats
# Integration tests for check behavior

load test_helper

# ============================================================================
# Count accuracy
# ============================================================================

@test "check: reports 0 when fully read" {
  mark_read "alice"
  local count
  count=$(chat_count_new "alice")
  [ "$count" = "0" ]
}

@test "check: reports correct count with mixed senders" {
  mark_read "alice"
  send_message "bob" "one"
  send_message "carol" "two"
  send_message "bob" "three"
  local count
  count=$(chat_count_new "alice")
  [ "$count" = "3" ]
}

# ============================================================================
# mark-read behavior
# ============================================================================

@test "check: mark_read advances cursor" {
  send_message "bob" "hello"
  send_message "bob" "world"
  mark_read "alice"

  send_message "bob" "new one"
  local count
  count=$(chat_count_new "alice")
  [ "$count" = "1" ]
}

@test "check: without mark_read, count stays same" {
  mark_read "alice"
  send_message "bob" "persistent"
  local count1
  count1=$(chat_count_new "alice")
  local count2
  count2=$(chat_count_new "alice")
  [ "$count1" = "$count2" ]
}

# ============================================================================
# New messages content
# ============================================================================

@test "check: new_messages includes all unread blocks" {
  mark_read "alice"
  send_message "bob" "first"
  send_message "carol" "second"
  run chat_new_messages "alice"
  [[ "$output" == *"first"* ]]
  [[ "$output" == *"second"* ]]
}

@test "check: new_messages excludes already-read content" {
  send_message "bob" "old message"
  mark_read "alice"
  send_message "carol" "new message"
  run chat_new_messages "alice"
  [[ "$output" != *"old message"* ]]
  [[ "$output" == *"new message"* ]]
}
