#!/usr/bin/env bats
# Integration tests for the send task

load test_helper

SEND="$REPO_DIR/.mise/tasks/send"

# Helper: run send task with isolated env
run_send() {
  CHAT_DATA_DIR="$CHAT_DATA_DIR" run bash "$SEND" "$@"
}

# ============================================================================
# Basic send
# ============================================================================

@test "send: appends message to chat file" {
  # Set usage vars that the task expects (normally set by mise/usage)
  export usage_from="alice" usage_chat="test-chat" usage_message="hello"
  run bash -c "source '$REPO_DIR/lib/chat.sh' && export CHAT_DATA_DIR='$CHAT_DATA_DIR' && bash '$SEND'"
  # Simpler: call lib directly since task depends on mise arg parsing
  send_message "alice" "hello from test"
  grep -q "hello from test" "$CHAT_FILE"
}

@test "send: message appears with sender header" {
  send_message "alice" "greetings"
  grep -q "^### alice — " "$CHAT_FILE"
}

# ============================================================================
# Validation (tested via lib, since task arg parsing needs mise)
# ============================================================================

@test "send: empty message handling" {
  # chat_append doesn't validate, but the task does
  # Test that an empty append still creates a header
  send_message "alice" ""
  grep -q "^### alice — " "$CHAT_FILE"
}

@test "send: multiline message preserved" {
  local msg=$'line one\nline two\nline three'
  send_message "alice" "$msg"
  grep -q "line one" "$CHAT_FILE"
  grep -q "line two" "$CHAT_FILE"
  grep -q "line three" "$CHAT_FILE"
}

# ============================================================================
# Send-before-read guard (tested via lib functions)
# ============================================================================

@test "send: guard — count_new detects unread" {
  send_message "bob" "hey alice"
  # Alice has cursor=0 (new), guard should skip
  local cursor
  cursor=$(chat_get_cursor "alice")
  [ "$cursor" = "0" ]

  # Now alice reads, then bob sends again
  mark_read "alice"
  send_message "bob" "another message"
  local unread
  unread=$(chat_count_new "alice")
  [ "$unread" -gt 0 ]
}

@test "send: guard — no unread after mark_read" {
  send_message "bob" "hello"
  mark_read "alice"
  local unread
  unread=$(chat_count_new "alice")
  [ "$unread" = "0" ]
}

@test "send: guard — cursor=0 means new agent, skip guard" {
  # New agent should have cursor 0
  local cursor
  cursor=$(chat_get_cursor "newagent")
  [ "$cursor" = "0" ]
  # Guard logic: if cursor > 0, check unread. cursor=0 -> skip.
  # This is what the task does — we verify the condition here.
}
