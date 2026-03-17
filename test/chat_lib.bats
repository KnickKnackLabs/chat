#!/usr/bin/env bats
# Unit tests for lib/chat.sh core functions

load test_helper

# ============================================================================
# chat_resolve
# ============================================================================

@test "resolve: explicit name sets CHAT_NAME" {
  chat_resolve "my-chat"
  [ "$CHAT_NAME" = "my-chat" ]
}

@test "resolve: explicit name sets CHAT_FILE" {
  chat_resolve "my-chat"
  [ "$CHAT_FILE" = "$CHAT_DATA_DIR/my-chat.md" ]
}

@test "resolve: explicit name sets CHAT_CURSOR_DIR" {
  chat_resolve "my-chat"
  [ "$CHAT_CURSOR_DIR" = "$CHAT_DATA_DIR/.cursors/my-chat" ]
}

@test "resolve: empty name falls back to global" {
  # No git repo in BATS_TMPDIR, so falls back
  CALLER_PWD="$BATS_TMPDIR" chat_resolve ""
  [ "$CHAT_NAME" = "global" ]
}

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

# ============================================================================
# chat_list
# ============================================================================

@test "list: includes current chat" {
  run chat_list
  [[ "$output" == *"test-chat"* ]]
}

@test "list: includes multiple chats" {
  # Create a second chat
  chat_resolve "other-chat"
  chat_init
  run chat_list
  [[ "$output" == *"test-chat"* ]]
  [[ "$output" == *"other-chat"* ]]
}

# ============================================================================
# chat_timestamp
# ============================================================================

@test "timestamp: matches YYYY-MM-DD HH:MM format" {
  local ts
  ts=$(chat_timestamp)
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]
}

# ============================================================================
# _chat_trim_trailing_newlines
# ============================================================================

@test "trim: removes trailing newlines" {
  local result
  result=$(_chat_trim_trailing_newlines $'hello\n\n\n')
  [ "$result" = "hello" ]
}

@test "trim: preserves internal newlines" {
  local result
  result=$(_chat_trim_trailing_newlines $'line1\nline2\n')
  [ "$result" = $'line1\nline2' ]
}

@test "trim: handles no trailing newline" {
  local result
  result=$(_chat_trim_trailing_newlines "clean")
  [ "$result" = "clean" ]
}

@test "trim: handles empty string" {
  local result
  result=$(_chat_trim_trailing_newlines "")
  [ "$result" = "" ]
}
