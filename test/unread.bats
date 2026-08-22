#!/usr/bin/env bats
# Task-level integration tests — exercise actual task scripts via chat() shim
#
# API v2: --as replaces --for/--from, implicit identity via $CHAT_IDENTITY,
# read absorbs check/log/messages, welcome renamed to status.

load test_helper

@test "task unread: zero total exits 0 with no output" {
  mark_read "alice"
  run chat unread --as alice
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "task unread: zero total JSON returns structured response" {
  mark_read "alice"
  run chat unread --as alice --json
  [ "$status" -eq 0 ]
  total=$(echo "$output" | jq '.total')
  [ "$total" -eq 0 ]
  channels=$(echo "$output" | jq '.channels | length')
  [ "$channels" -eq 0 ]
}

@test "task unread: sums across channels" {
  # Create a second channel
  CHAT_NAME="other-chat"
  CHAT_FILE="$CHAT_DATA_DIR/other-chat.md"
  CHAT_CURSOR_DIR="$CHAT_DATA_DIR/.cursors/other-chat"
  chat_init

  # Mark both as read, then send messages
  chat_resolve "test-chat"
  mark_read "alice"
  send_message "bob" "msg1"
  send_message "bob" "msg2"

  chat_resolve "other-chat"
  mark_read "alice"
  send_message "carol" "msg3"

  run chat unread --as alice
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "task unread: excludes own messages" {
  mark_read "alice"
  send_message "alice" "my own message"
  send_message "bob" "from bob"
  run chat unread --as alice
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "task unread: JSON shows per-channel breakdown" {
  # Create a second channel
  CHAT_NAME="other-chat"
  CHAT_FILE="$CHAT_DATA_DIR/other-chat.md"
  CHAT_CURSOR_DIR="$CHAT_DATA_DIR/.cursors/other-chat"
  chat_init

  chat_resolve "test-chat"
  mark_read "alice"
  send_message "bob" "msg1"

  chat_resolve "other-chat"
  mark_read "alice"
  send_message "carol" "msg2"
  send_message "carol" "msg3"

  run chat unread --as alice --json
  [ "$status" -eq 0 ]
  total=$(echo "$output" | jq '.total')
  [ "$total" -eq 3 ]
  test_count=$(echo "$output" | jq '.channels["test-chat"]')
  [ "$test_count" -eq 1 ]
  other_count=$(echo "$output" | jq '.channels["other-chat"]')
  [ "$other_count" -eq 2 ]
}

@test "task unread: no channels exits 0" {
  # Remove all chat files
  rm -f "$CHAT_DATA_DIR"/*.md
  run chat unread --as alice
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
