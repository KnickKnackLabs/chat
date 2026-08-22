#!/usr/bin/env bats
# Task-level integration tests — exercise actual task scripts via chat() shim
#
# API v2: --as replaces --for/--from, implicit identity via $CHAT_IDENTITY,
# read absorbs check/log/messages, welcome renamed to status.

load test_helper

@test "task send: appends message" {
  run chat send --as alice --chat test-chat --msg "hello world"
  [ "$status" -eq 0 ]
  grep -q "hello world" "$CHAT_FILE"
}

@test "task send: message has sender header" {
  run chat send --as alice --chat test-chat --msg "test"
  [ "$status" -eq 0 ]
  grep -q "^### alice" "$CHAT_FILE"
}

@test "task send: confirms with output" {
  run chat send --as alice --chat test-chat --msg "hi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sent to test-chat"* ]]
}

@test "task send: CHAT_IDENTITY env var used when --as omitted" {
  CHAT_IDENTITY="alice" run chat send --chat test-chat --msg "env identity send"
  [ "$status" -eq 0 ]
  grep -q "### alice" "$CHAT_FILE"
  grep -q "env identity send" "$CHAT_FILE"
}

@test "task send: fails without identity" {
  unset CHAT_IDENTITY
  run chat send --chat test-chat --msg "no identity"
  [ "$status" -ne 0 ]
  [[ "$output" == *"identity required"* ]]
}

@test "task send: rejects empty message" {
  run chat send --as alice --chat test-chat --msg ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty"* ]]
}

@test "task send: rejects message over 10 lines" {
  local long_msg
  long_msg=$(printf 'line %s\n' $(seq 1 11))
  run chat send --as alice --chat test-chat --msg "$long_msg"
  [ "$status" -ne 0 ]
  [[ "$output" == *"too long"* ]]
}

@test "task send: allows message at exactly 10 lines" {
  local msg
  msg=$(printf 'line %s\n' $(seq 1 10))
  run chat send --as alice --chat test-chat --msg "$msg"
  [ "$status" -eq 0 ]
}

@test "task send: guard blocks send when unread messages exist" {
  # alice sends first message (cursor stays 0 — new agent, guard skips)
  run chat send --as alice --chat test-chat --msg "first"
  [ "$status" -eq 0 ]

  # alice reads to set cursor > 0
  mark_read "alice"

  # bob sends a message alice hasn't read
  send_message "bob" "unread msg"

  # alice tries to send — guard should block and show the unread message inline
  run chat send --as alice --chat test-chat --msg "blocked"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Aborted: you have 1 unread message(s) in test-chat."* ]]
  [[ "$output" == *"unread msg"* ]]
  [[ "$output" == *"To send anyway, use: chat send --force"* ]]
}

@test "task send: guard preview omits sender's own unread messages" {
  send_message "alice" "setup"
  mark_read "alice"

  send_message "bob" "blocking msg"
  send_message "alice" "own one"
  send_message "alice" "own two"
  send_message "alice" "own three"

  run chat send --as alice --chat test-chat --msg "blocked"
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocking msg"* ]]
  [[ "$output" != *"own one"* ]]
  [[ "$output" != *"own two"* ]]
  [[ "$output" != *"own three"* ]]
}

@test "task send: --force bypasses unread guard" {
  run chat send --as alice --chat test-chat --msg "first"
  [ "$status" -eq 0 ]
  mark_read "alice"
  send_message "bob" "unread"

  run chat send --as alice --chat test-chat --msg "forced" --force
  [ "$status" -eq 0 ]
  grep -q "forced" "$CHAT_FILE"
}

@test "task send: omitted --force ignores stale usage_force env" {
  run chat send --as alice --chat test-chat --msg "first"
  [ "$status" -eq 0 ]
  mark_read "alice"
  send_message "bob" "unread"

  usage_force=true run chat send --as alice --chat test-chat --msg "blocked"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Aborted: you have 1 unread message(s) in test-chat."* ]]
}

@test "task send: new agent (cursor=0) bypasses guard" {
  # bob has never read — cursor is 0
  send_message "carol" "some message"
  # bob should be able to send despite carol's unread message
  run chat send --as bob --chat test-chat --msg "hi from bob"
  [ "$status" -eq 0 ]
}

@test "task send: new agent can send multiple times without reading (cursor=0)" {
  # alice has never read — cursor stays at 0, guard is skipped
  run chat send --as alice --chat test-chat --msg "first msg"
  [ "$status" -eq 0 ]

  # alice sends again — still cursor=0, guard still skipped
  run chat send --as alice --chat test-chat --msg "second msg"
  [ "$status" -eq 0 ]
  grep -q "second msg" "$CHAT_FILE"
}

@test "task send: own unread messages do not trigger guard" {
  # alice sends and reads to set cursor > 0
  send_message "alice" "setup"
  mark_read "alice"

  # alice sends — her own message is now "unread" (cursor didn't advance)
  run chat send --as alice --chat test-chat --msg "first from alice"
  [ "$status" -eq 0 ]

  # alice sends again — guard should NOT block (only own messages are unread)
  run chat send --as alice --chat test-chat --msg "second from alice"
  [ "$status" -eq 0 ]
  grep -q "second from alice" "$CHAT_FILE"
}

@test "task send: does not advance sender cursor" {
  # alice sends, then reads (cursor > 0)
  send_message "alice" "setup"
  mark_read "alice"

  # bob sends a message alice hasn't read
  send_message "bob" "hey alice"

  # alice sends with --force to bypass the guard
  run chat send --as alice --chat test-chat --force --msg "replying without reading"
  [ "$status" -eq 0 ]

  # alice's cursor should NOT have advanced — bob's message is still unread
  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"hey alice"* ]]
}

@test "task send: bare token errors instead of sending" {
  run chat send den
  [ "$status" -ne 0 ]
}

@test "task send: omitted --msg ignores stale usage_msg env" {
  usage_msg="stale inherited message" run chat send --as alice --chat test-chat
  [ "$status" -ne 0 ]
  ! grep -q "stale inherited message" "$CHAT_FILE"
}

@test "task send: creates channel that did not exist" {
  run chat send --as alice --chat brand-new-channel --msg "first message"
  [ "$status" -eq 0 ]
  [ -f "$CHAT_DATA_DIR/brand-new-channel.md" ]
  grep -q "first message" "$CHAT_DATA_DIR/brand-new-channel.md"
}
