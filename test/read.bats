#!/usr/bin/env bats
# Task-level integration tests — exercise actual task scripts via chat() shim
#
# API v2: --as replaces --for/--from, implicit identity via $CHAT_IDENTITY,
# read absorbs check/log/messages, welcome renamed to status.

load test_helper

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

@test "task read: fails on non-existent channel" {
  run chat read no-such-channel
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task read: does not create file for non-existent channel" {
  run chat read no-such-channel
  [ ! -f "$CHAT_DATA_DIR/no-such-channel.md" ]
}
