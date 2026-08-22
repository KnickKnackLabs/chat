#!/usr/bin/env bats
# Task-level integration tests — exercise actual task scripts via chat() shim
#
# API v2: --as replaces --for/--from, implicit identity via $CHAT_IDENTITY,
# read absorbs check/log/messages, welcome renamed to status.

load test_helper

@test "task wait: --by gates on sender and prints unseen context" {
  mark_read "alice"
  send_message "bob" "context before gate"
  send_message "or" "gate from or"

  run chat wait test-chat --as alice --by or --timeout 1 --poll 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"context before gate"* ]]
  [[ "$output" == *"gate from or"* ]]
}

@test "task wait: --from is an alias for --by" {
  mark_read "alice"
  send_message "or" "from alias gate"

  run chat wait test-chat --as alice --from or --timeout 1 --poll 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"from alias gate"* ]]
}

@test "task wait: --by times out when sender does not match" {
  mark_read "alice"
  send_message "bob" "not from or"

  run chat wait test-chat --as alice --by or --timeout 1 --poll 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Timed out"* ]]
  [[ "$output" == *"no matching messages"* ]]
}

@test "task wait: --mentioned gates on waiting identity mention" {
  mark_read "alice"
  send_message "bob" "context before mention"
  send_message "or" "hey @alice"

  run chat wait test-chat --as alice --mentioned --timeout 1 --poll 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"context before mention"* ]]
  [[ "$output" == *"hey @alice"* ]]
}

@test "task wait: --mentioned requires identity" {
  unset CHAT_IDENTITY
  run chat wait test-chat --mentioned --timeout 1 --poll 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"--mentioned requires an identity"* ]]
}

@test "task wait: --mention gates on explicit mention" {
  mark_read "alice"
  send_message "bob" "hello @carol"

  run chat wait test-chat --as alice --mention carol --timeout 1 --poll 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello @carol"* ]]
}

@test "task wait: --mentioned does not prefix-match longer identities" {
  mark_read "ann"
  send_message "bob" "hello @anna"

  run chat wait test-chat --as ann --mentioned --timeout 1 --poll 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Timed out"* ]]
}

@test "task wait: --mentioned accepts punctuation-delimited mention" {
  mark_read "ann"
  send_message "bob" "hello @ann, please look"

  run chat wait test-chat --as ann --mentioned --timeout 1 --poll 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello @ann, please look"* ]]
}

@test "task wait: fails on non-existent channel" {
  run chat wait no-such-channel --timeout 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}
