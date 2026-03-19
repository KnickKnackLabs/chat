#!/usr/bin/env bats
# Task-level integration tests — exercise actual task scripts
#
# API v2: --as replaces --for/--from, implicit identity via $CHAT_IDENTITY,
# read absorbs check/log/messages, welcome renamed to status.

load test_helper

# ============================================================================
# read task
# ============================================================================

@test "task read: no new messages exits 0" {
  mark_read "alice"
  run_task read --as alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"No new messages"* ]]
}

@test "task read: shows unread messages" {
  mark_read "alice"
  send_message "bob" "hey alice"
  run_task read --as alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"hey alice"* ]]
}

@test "task read: advances cursor after reading" {
  mark_read "alice"
  send_message "bob" "msg1"
  run_task read --as alice --chat test-chat
  [ "$status" -eq 0 ]

  # Second read should show no new messages
  run_task read --as alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"No new messages"* ]]
}

@test "task read: --peek does not advance cursor" {
  mark_read "alice"
  send_message "bob" "peeked"
  local cursor_before
  cursor_before=$(chat_get_cursor "alice")

  run_task read --as alice --chat test-chat --peek
  [ "$status" -eq 0 ]
  [[ "$output" == *"peeked"* ]]

  local cursor_after
  cursor_after=$(chat_get_cursor "alice")
  [ "$cursor_before" = "$cursor_after" ]
}

@test "task read: --all shows everything" {
  send_message "bob" "visible"
  mark_read "alice"
  send_message "carol" "also visible"
  run_task read --as alice --chat test-chat --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"visible"* ]]
  [[ "$output" == *"also visible"* ]]
}

@test "task read: without --as uses spectator mode (shows all)" {
  send_message "bob" "hello"
  run_task read --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
}

@test "task read: CHAT_IDENTITY env var used when --as omitted" {
  mark_read "alice"
  send_message "bob" "env-identity test"
  run env CHAT_DATA_DIR="$CHAT_DATA_DIR" CHAT_IDENTITY="alice" \
    mise run -C "$REPO_DIR" read -- --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"env-identity test"* ]]
}

@test "task read: --from filters by sender" {
  mark_read "alice"
  send_message "bob" "from bob"
  send_message "carol" "from carol"
  run_task read --as alice --chat test-chat --from bob
  [ "$status" -eq 0 ]
  [[ "$output" == *"from bob"* ]]
  [[ "$output" != *"from carol"* ]]
}

@test "task read: --all --last shows last N messages" {
  send_message "alice" "first"
  send_message "bob" "second"
  send_message "carol" "third"
  run_task read --chat test-chat --all --last 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"third"* ]]
  [[ "$output" != *"first"* ]]
}

@test "task read: cursor advances after reading messages" {
  send_message "bob" "setup"
  mark_read "alice"

  local cursor_before
  cursor_before=$(chat_get_cursor "alice")

  send_message "bob" "new"
  run_task read --as alice --chat test-chat
  [ "$status" -eq 0 ]

  local cursor_after
  cursor_after=$(chat_get_cursor "alice")
  [ "$cursor_after" -gt "$cursor_before" ]
}

# ============================================================================
# send task
# ============================================================================

@test "task send: appends message" {
  run_task send --as alice --chat test-chat "hello world"
  [ "$status" -eq 0 ]
  grep -q "hello world" "$CHAT_FILE"
}

@test "task send: message has sender header" {
  run_task send --as alice --chat test-chat "test"
  [ "$status" -eq 0 ]
  grep -q "^### alice" "$CHAT_FILE"
}

@test "task send: confirms with output" {
  run_task send --as alice --chat test-chat "hi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sent to test-chat"* ]]
}

@test "task send: CHAT_IDENTITY env var used when --as omitted" {
  run env CHAT_DATA_DIR="$CHAT_DATA_DIR" CHAT_IDENTITY="alice" \
    mise run -C "$REPO_DIR" send -- --chat test-chat "env identity send"
  [ "$status" -eq 0 ]
  grep -q "### alice" "$CHAT_FILE"
  grep -q "env identity send" "$CHAT_FILE"
}

@test "task send: fails without identity" {
  run env CHAT_DATA_DIR="$CHAT_DATA_DIR" \
    mise run -C "$REPO_DIR" send -- --chat test-chat "no identity"
  [ "$status" -ne 0 ]
  [[ "$output" == *"identity required"* ]]
}

@test "task send: rejects empty message" {
  run_task send --as alice --chat test-chat ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty"* ]]
}

@test "task send: rejects message over 10 lines" {
  local long_msg
  long_msg=$(printf 'line %s\n' $(seq 1 11))
  run_task send --as alice --chat test-chat "$long_msg"
  [ "$status" -ne 0 ]
  [[ "$output" == *"too long"* ]]
}

@test "task send: allows message at exactly 10 lines" {
  local msg
  msg=$(printf 'line %s\n' $(seq 1 10))
  run_task send --as alice --chat test-chat "$msg"
  [ "$status" -eq 0 ]
}

@test "task send: guard blocks send when unread messages exist" {
  # alice sends first message (cursor stays 0 — new agent, guard skips)
  run_task send --as alice --chat test-chat "first"
  [ "$status" -eq 0 ]

  # alice reads to set cursor > 0
  mark_read "alice"

  # bob sends a message alice hasn't read
  send_message "bob" "unread msg"

  # alice tries to send — guard should block
  run_task send --as alice --chat test-chat "blocked"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unread"* ]]
}

@test "task send: --force bypasses unread guard" {
  run_task send --as alice --chat test-chat "first"
  [ "$status" -eq 0 ]
  mark_read "alice"
  send_message "bob" "unread"

  run_task send --as alice --chat test-chat "forced" --force
  [ "$status" -eq 0 ]
  grep -q "forced" "$CHAT_FILE"
}

@test "task send: new agent (cursor=0) bypasses guard" {
  # bob has never read — cursor is 0
  send_message "carol" "some message"
  # bob should be able to send despite carol's unread message
  run_task send --as bob --chat test-chat "hi from bob"
  [ "$status" -eq 0 ]
}

# ============================================================================
# status task (replaces welcome)
# ============================================================================

@test "task status: shows chat name" {
  run_task status --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-chat"* ]]
}

@test "task status: shows unread count with --as" {
  send_message "bob" "hey"
  run_task status --as alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"unread"* ]]
}

@test "task status: shows no unread when fully read" {
  mark_read "alice"
  run_task status --as alice --chat test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"No unread"* ]]
}
