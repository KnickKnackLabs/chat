#!/usr/bin/env bats
# Read, send, and sig task integration tests

load test_helper

# ============================================================================
# read task
# ============================================================================

@test "task read: no new messages exits 0" {
  mark_read "alice"
  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"No new messages"* ]]
}

@test "task read: shows unread messages" {
  mark_read "alice"
  send_message "bob" "hey alice"
  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"hey alice"* ]]
}

@test "task read: advances cursor after reading" {
  mark_read "alice"
  send_message "bob" "msg1"
  run chat read test-chat --as alice
  [ "$status" -eq 0 ]

  # Second read should show no new messages
  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"No new messages"* ]]
}

@test "task read: no channel inferred fails with a clear diagnostic" {
  # No positional channel and no $CHAT_CHANNEL → default is inferred but absent.
  run chat read --as alice
  [ "$status" -ne 0 ]
  [[ "$output" == *"no chat channel"* ]]
}

@test "task read: --peek does not advance cursor" {
  mark_read "alice"
  send_message "bob" "peeked"
  local cursor_before
  cursor_before=$(chat_get_cursor "alice")

  run chat read test-chat --as alice --peek
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
  run chat read test-chat --as alice --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"visible"* ]]
  [[ "$output" == *"also visible"* ]]
}

@test "task read: without --as uses spectator mode (shows all)" {
  send_message "bob" "hello"
  run chat read test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
}

@test "task read: CHAT_IDENTITY env var used when --as omitted" {
  mark_read "alice"
  send_message "bob" "env-identity test"
  CHAT_IDENTITY="alice" run chat read test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"env-identity test"* ]]
}

@test "task read: no chat argument ignores package caller-pwd context" {
  _setup_git_remote "https://github.com/KnickKnackLabs/chat.git"
  chat_resolve "default"
  chat_init
  chat_append "bob" "default-channel message"

  export CHAT_CALLER_PWD="$BATS_TEST_TMPDIR/fakerepo"
  run chat read --as alice --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"default-channel message"* ]]
}

@test "task read: --by filters by sender" {
  mark_read "alice"
  send_message "bob" "from bob"
  send_message "carol" "from carol"
  run chat read test-chat --as alice --by bob
  [ "$status" -eq 0 ]
  [[ "$output" == *"from bob"* ]]
  [[ "$output" != *"from carol"* ]]
}

@test "task read: omitted --by ignores stale usage_by env" {
  send_message "bob" "from bob"
  send_message "carol" "from carol"
  usage_by=bob run chat read test-chat --as alice --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"from bob"* ]]
  [[ "$output" == *"from carol"* ]]
}

@test "task read: --all --last shows last N messages" {
  send_message "alice" "first"
  send_message "bob" "second"
  send_message "carol" "third"
  run chat read test-chat --all --last 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"third"* ]]
  [[ "$output" != *"first"* ]]
}

@test "task read: --last implies --all (shows past cursor)" {
  send_message "alice" "old"
  send_message "bob" "also old"
  mark_read "carol"
  send_message "alice" "new"
  # carol's cursor is past "old" and "also old", but --last 3 should show all 3
  run chat read test-chat --as carol --last 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"old"* ]]
  [[ "$output" == *"also old"* ]]
  [[ "$output" == *"new"* ]]
}

@test "task read: --by implies --all (shows past cursor)" {
  send_message "alice" "before cursor"
  mark_read "bob"
  send_message "alice" "after cursor"
  # bob's cursor is past "before cursor", but --by alice should show both
  run chat read test-chat --as bob --by alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"before cursor"* ]]
  [[ "$output" == *"after cursor"* ]]
}

@test "task read: cursor advances after reading messages" {
  send_message "bob" "setup"
  mark_read "alice"

  local cursor_before
  cursor_before=$(chat_get_cursor "alice")

  send_message "bob" "new"
  run chat read test-chat --as alice
  [ "$status" -eq 0 ]

  local cursor_after
  cursor_after=$(chat_get_cursor "alice")
  [ "$cursor_after" -gt "$cursor_before" ]
}

@test "task read: invalid chat file format fails closed" {
  cat > "$CHAT_FILE" <<'BAD'
# malformed

Shared communication channel.

---
not a frontmatter message block
BAD

  run chat read test-chat --as alice
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid chat file format"* ]]
}

# ============================================================================
# send task
# ============================================================================

@test "task send: appends message" {
  run chat send --as alice --chat test-chat --msg "hello world"
  [ "$status" -eq 0 ]
  grep -q "hello world" "$CHAT_FILE"
}

@test "task send: message has sender header" {
  run chat send --as alice --chat test-chat --msg "test"
  [ "$status" -eq 0 ]
  grep -q "^from: alice$" "$CHAT_FILE"
}

@test "task send: confirms with output" {
  run chat send --as alice --chat test-chat --msg "hi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sent to test-chat"* ]]
}

@test "task send: CHAT_IDENTITY env var used when --as omitted" {
  CHAT_IDENTITY="alice" run chat send --chat test-chat --msg "env identity send"
  [ "$status" -eq 0 ]
  grep -q "^from: alice$" "$CHAT_FILE"
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

# ============================================================================
# sig task
# ============================================================================

@test "task sig: sets and shows signature" {
  run chat sig --as alice "sent from pi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Signature set for alice."* ]]

  run chat sig --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Signature for alice:"* ]]
  [[ "$output" == *"sent from pi"* ]]
}

@test "task sig: send appends signature" {
  run chat sig --as alice "sent from pi"
  [ "$status" -eq 0 ]

  run chat send --as alice --chat test-chat --msg "hello"
  [ "$status" -eq 0 ]
  grep -q "hello" "$CHAT_FILE"
  grep -q '^--$' "$CHAT_FILE"
  grep -q "sent from pi" "$CHAT_FILE"
}

@test "task sig: clear removes signature" {
  run chat sig --as alice "sent from pi"
  [ "$status" -eq 0 ]

  run chat sig --as alice --clear
  [ "$status" -eq 0 ]
  [[ "$output" == *"Signature cleared for alice."* ]]

  run chat send --as alice --chat test-chat --msg "hello"
  [ "$status" -eq 0 ]
  grep -q "hello" "$CHAT_FILE"
  ! grep -q "sent from pi" "$CHAT_FILE"
}

@test "task sig: rejects clear with signature text" {
  run chat sig --as alice --clear "sent from pi"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not both"* ]]
}

@test "task sig: omitted --clear ignores stale usage_clear env" {
  usage_clear=true run chat sig --as alice "sent from pi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Signature set for alice."* ]]

  run chat sig --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"sent from pi"* ]]
}

