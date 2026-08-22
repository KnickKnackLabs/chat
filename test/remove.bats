#!/usr/bin/env bats
# Task-level integration tests — exercise actual task scripts via chat() shim
#
# API v2: --as replaces --for/--from, implicit identity via $CHAT_IDENTITY,
# read absorbs check/log/messages, welcome renamed to status.

load test_helper

@test "task remove: deletes channel file and cursor dir" {
  send_message "alice" "hello"
  mark_read "alice"
  [ -f "$CHAT_FILE" ]
  [ -d "$CHAT_CURSOR_DIR" ]

  run chat remove test-chat --yes
  [ "$status" -eq 0 ]
  [ ! -f "$CHAT_FILE" ]
  [ ! -d "$CHAT_CURSOR_DIR" ]
  [[ "$output" == *"Removed"* ]]
}

@test "task remove: fails on non-existent channel" {
  run chat remove no-such-channel --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task remove: refuses to remove default channel" {
  chat_resolve "default"
  chat_init
  run chat remove default --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot remove the default channel"* ]]
  [ -f "$CHAT_DATA_DIR/default.md" ]
}

@test "task remove: refuses to remove legacy global channel" {
  chat_resolve "global"
  chat_init
  run chat remove global --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot remove the global channel"* ]]
  [ -f "$CHAT_DATA_DIR/global.md" ]
}

@test "task remove: channel no longer appears in list" {
  send_message "alice" "hello"
  run chat list --json
  echo "$output" | python3 -c "
import json, sys
names = [c['name'] for c in json.load(sys.stdin)]
assert 'test-chat' in names, f'expected test-chat in {names}'
"

  run chat remove test-chat --yes
  [ "$status" -eq 0 ]

  run chat list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
names = [c['name'] for c in json.load(sys.stdin)]
assert 'test-chat' not in names, f'test-chat should be gone, got {names}'
"
}
