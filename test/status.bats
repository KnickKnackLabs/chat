#!/usr/bin/env bats
# Task-level integration tests — exercise actual task scripts via chat() shim
#
# API v2: --as replaces --for/--from, implicit identity via $CHAT_IDENTITY,
# read absorbs check/log/messages, welcome renamed to status.

load test_helper

@test "task status: shows chat name" {
  run chat status test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-chat"* ]]
}

@test "task status: shows unread count with --as" {
  send_message "bob" "hey"
  run chat status test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unread"* ]]
}

@test "task status: hides unread row when fully read" {
  mark_read "alice"
  run chat status test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" != *"Unread"* ]]
}

@test "task status --json: outputs valid JSON" {
  send_message "alice" "hello"
  run chat status test-chat --as bob --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)"
}

@test "task status --json: includes unread count with --as" {
  send_message "alice" "msg1"
  send_message "alice" "msg2"
  run chat status test-chat --as bob --json
  [ "$status" -eq 0 ]
  local unread
  unread=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['unread'])")
  [ "$unread" = "2" ]
}

@test "task status --json: unread is 0 when fully read" {
  send_message "alice" "hello"
  mark_read "bob"
  run chat status test-chat --as bob --json
  [ "$status" -eq 0 ]
  local unread
  unread=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['unread'])")
  [ "$unread" = "0" ]
}

@test "task status --json: omits unread when no --as" {
  send_message "alice" "hello"
  unset CHAT_IDENTITY
  run chat status test-chat --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert 'unread' not in data, f'unread should not be present without --as, got: {data}'
"
}

@test "task status --json: no human-readable header in output" {
  send_message "alice" "hello"
  run chat status test-chat --as alice --json
  [ "$status" -eq 0 ]
  # First non-empty char should be '{' (JSON object)
  local first_char
  first_char=$(echo "$output" | head -c 1)
  [ "$first_char" = "{" ]
}

@test "task status: fails on non-existent channel" {
  run chat status no-such-channel
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}
