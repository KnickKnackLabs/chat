#!/usr/bin/env bats
# Task-level integration tests — exercise actual task scripts with set -eo pipefail
#
# These tests catch bugs that library-level tests miss, because the tasks
# have set -eo pipefail and use usage_* env vars from mise.

load test_helper

# ============================================================================
# read task
# ============================================================================

@test "task read: no new messages exits 0" {
  mark_read "alice"
  run_task read --for alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"No new messages"* ]]
}

@test "task read: shows unread messages" {
  mark_read "alice"
  send_message "bob" "hey alice"
  run_task read --for alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"hey alice"* ]]
}

@test "task read: advances cursor after reading" {
  mark_read "alice"
  send_message "bob" "msg1"
  run_task read --for alice --chat test-chat
  [ "$status" -eq 0 ]

  # Second read should show no new messages
  run_task read --for alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"No new messages"* ]]
}

@test "task read: --all shows everything" {
  send_message "bob" "visible"
  mark_read "alice"
  send_message "carol" "also visible"
  run_task read --for alice --chat test-chat --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"visible"* ]]
  [[ "$output" == *"also visible"* ]]
}

@test "task read: without --for uses spectator mode (shows all)" {
  send_message "bob" "hello"
  run_task read --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
}

@test "task read: --from filters by sender" {
  mark_read "alice"
  send_message "bob" "from bob"
  send_message "carol" "from carol"
  run_task read --for alice --chat test-chat --from bob
  [ "$status" -eq 0 ]
  [[ "$output" == *"from bob"* ]]
  [[ "$output" != *"from carol"* ]]
}

@test "task read: cursor advances after reading messages" {
  send_message "bob" "setup"
  mark_read "alice"

  # Verify cursor is at current position
  local cursor_before
  cursor_before=$(chat_get_cursor "alice")

  # Send a message, then mark read via the task
  send_message "bob" "new"
  run_task read --for alice --chat test-chat
  [ "$status" -eq 0 ]

  local cursor_after
  cursor_after=$(chat_get_cursor "alice")
  [ "$cursor_after" -gt "$cursor_before" ]
}

# ============================================================================
# check task
# ============================================================================

@test "task check: no messages exits 0" {
  mark_read "alice"
  run_task check --for alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"No new messages"* ]]
}

@test "task check: reports count of new messages" {
  mark_read "alice"
  send_message "bob" "one"
  send_message "carol" "two"
  run_task check --for alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 new message"* ]]
}

@test "task check: --mark-read advances cursor" {
  mark_read "alice"
  send_message "bob" "hello"
  run_task check --for alice --chat test-chat --mark-read
  [ "$status" -eq 0 ]

  # Should now be zero
  local count
  count=$(chat_count_new "alice")
  [ "$count" = "0" ]
}

# ============================================================================
# send task
# ============================================================================

@test "task send: appends message" {
  run_task send --from alice --chat test-chat "hello world"
  [ "$status" -eq 0 ]
  grep -q "hello world" "$CHAT_FILE"
}

@test "task send: message has sender header" {
  run_task send --from alice --chat test-chat "test"
  [ "$status" -eq 0 ]
  grep -q "^### alice" "$CHAT_FILE"
}

@test "task send: confirms with output" {
  run_task send --from alice --chat test-chat "hi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sent to test-chat"* ]]
}

@test "task send: rejects empty message" {
  run_task send --from alice --chat test-chat ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty"* ]]
}

@test "task send: rejects message over 10 lines" {
  local long_msg
  long_msg=$(printf 'line %s\n' $(seq 1 11))
  run_task send --from alice --chat test-chat "$long_msg"
  [ "$status" -ne 0 ]
  [[ "$output" == *"too long"* ]]
}

@test "task send: allows message at exactly 10 lines" {
  local msg
  msg=$(printf 'line %s\n' $(seq 1 10))
  run_task send --from alice --chat test-chat "$msg"
  [ "$status" -eq 0 ]
}

@test "task send: guard blocks send when unread messages exist" {
  # alice sends first message (cursor stays 0 — new agent, guard skips)
  run_task send --from alice --chat test-chat "first"
  [ "$status" -eq 0 ]

  # alice reads to set cursor > 0
  mark_read "alice"

  # bob sends a message alice hasn't read
  send_message "bob" "unread msg"

  # alice tries to send — guard should block
  run_task send --from alice --chat test-chat "blocked"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unread"* ]]
}

@test "task send: --force bypasses unread guard" {
  run_task send --from alice --chat test-chat "first"
  [ "$status" -eq 0 ]
  mark_read "alice"
  send_message "bob" "unread"

  run_task send --from alice --chat test-chat "forced" --force
  [ "$status" -eq 0 ]
  grep -q "forced" "$CHAT_FILE"
}

@test "task send: new agent (cursor=0) bypasses guard" {
  # bob has never read — cursor is 0
  send_message "carol" "some message"
  # bob should be able to send despite carol's unread message
  run_task send --from bob --chat test-chat "hi from bob"
  [ "$status" -eq 0 ]
}

# ============================================================================
# check task (additional)
# ============================================================================

@test "task check: without --mark-read leaves cursor unchanged" {
  mark_read "alice"
  send_message "bob" "hello"
  local cursor_before
  cursor_before=$(chat_get_cursor "alice")

  run_task check --for alice --chat test-chat
  [ "$status" -eq 0 ]

  local cursor_after
  cursor_after=$(chat_get_cursor "alice")
  [ "$cursor_before" = "$cursor_after" ]
}

@test "task check: shows message content" {
  mark_read "alice"
  send_message "bob" "specific content here"
  run_task check --for alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"specific content here"* ]]
}
