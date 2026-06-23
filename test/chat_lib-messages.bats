#!/usr/bin/env bats
bats_require_minimum_version 1.10.0
# Unit tests for lib/chat.sh core functions

load test_helper
# ============================================================================
# chat_append
# ============================================================================

@test "append: adds message to file" {
  local before
  before=$(chat_line_count)
  send_message "alice" "hello world"
  local after
  after=$(chat_line_count)
  [ "$after" -gt "$before" ]
}

@test "append: message has correct header format" {
  send_message "alice" "test message"
  grep -q "^### alice — " "$CHAT_FILE"
}

@test "append: message body is preserved" {
  send_message "alice" "exact content here"
  grep -q "exact content here" "$CHAT_FILE"
}

@test "append: multiple messages accumulate" {
  send_message "alice" "msg1"
  send_message "bob" "msg2"
  send_message "alice" "msg3"
  local count
  count=$(grep -c "^### " "$CHAT_FILE")
  [ "$count" -eq 3 ]
}

@test "append: multiline message preserved" {
  local msg=$'line one\nline two\nline three'
  send_message "alice" "$msg"
  grep -q "line one" "$CHAT_FILE"
  grep -q "line two" "$CHAT_FILE"
  grep -q "line three" "$CHAT_FILE"
}

@test "append: empty body still creates header" {
  send_message "alice" ""
  grep -q "^### alice — " "$CHAT_FILE"
}

# ============================================================================
# chat_new_messages
# ============================================================================

@test "new_messages: returns 1 when no new messages" {
  mark_read "alice"
  run chat_new_messages "alice"
  [ "$status" -eq 1 ]
}

@test "new_messages: returns content after cursor" {
  mark_read "alice"
  send_message "bob" "new stuff"
  run chat_new_messages "alice"
  [ "$status" -eq 0 ]
  [[ "$output" == *"new stuff"* ]]
}

@test "new_messages: includes header" {
  mark_read "alice"
  send_message "bob" "hello"
  run chat_new_messages "alice"
  [[ "$output" == *"### bob"* ]]
}

@test "new_messages: excludes already-read content" {
  send_message "bob" "old message"
  mark_read "alice"
  send_message "carol" "new message"
  run chat_new_messages "alice"
  [[ "$output" == *"new message"* ]]
  [[ "$output" != *"old message"* ]]
}

@test "new_messages: independent readers see different content" {
  send_message "carol" "msg for everyone"
  mark_read "alice"
  send_message "carol" "msg2"

  # alice only sees msg2
  run chat_new_messages "alice"
  [[ "$output" == *"msg2"* ]]
  [[ "$output" != *"msg for everyone"* ]]

  # bob (cursor=0) sees everything from start
  local bob_cursor
  bob_cursor=$(chat_get_cursor "bob")
  [ "$bob_cursor" = "0" ]
}

@test "new_messages: cursor beyond file length returns 1" {
  printf '99999' > "$CHAT_CURSOR_DIR/alice"
  run chat_new_messages "alice"
  [ "$status" -eq 1 ]
}

# ============================================================================
# chat_count_new
# ============================================================================

@test "count_new: 0 when fully read" {
  mark_read "alice"
  local count
  count=$(chat_count_new "alice")
  [ "$count" = "0" ]
}

@test "count_new: counts message blocks correctly" {
  mark_read "alice"
  send_message "bob" "msg1"
  send_message "carol" "msg2"
  send_message "bob" "msg3"
  local count
  count=$(chat_count_new "alice")
  [ "$count" = "3" ]
}

@test "count_new: 0 for new agent with no messages after header" {
  # New agent, cursor=0, but file only has the init header
  # chat_count_new with cursor 0 will count ### headers in the whole file
  # Since init doesn't add ### headers, count should be 0
  local count
  count=$(chat_count_new "newbie")
  [ "$count" = "0" ]
}

@test "count_new: repeated calls return same value (no side effects)" {
  mark_read "alice"
  send_message "bob" "persistent"
  local count1 count2
  count1=$(chat_count_new "alice")
  count2=$(chat_count_new "alice")
  [ "$count1" = "$count2" ]
}

@test "count_new: excludes own messages" {
  mark_read "alice"
  send_message "alice" "my own msg"
  send_message "alice" "another of mine"
  local count
  count=$(chat_count_new "alice")
  [ "$count" = "0" ]
}

@test "count_new: counts only others when mixed" {
  mark_read "alice"
  send_message "alice" "mine"
  send_message "bob" "from bob"
  send_message "alice" "mine again"
  local count
  count=$(chat_count_new "alice")
  [ "$count" = "1" ]
}

