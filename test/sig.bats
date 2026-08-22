#!/usr/bin/env bats
# Task-level integration tests — exercise actual task scripts via chat() shim
#
# API v2: --as replaces --for/--from, implicit identity via $CHAT_IDENTITY,
# read absorbs check/log/messages, welcome renamed to status.

load test_helper

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
