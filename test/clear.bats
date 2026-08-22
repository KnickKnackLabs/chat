#!/usr/bin/env bats
# Task-level integration tests — exercise actual task scripts via chat() shim
#
# API v2: --as replaces --for/--from, implicit identity via $CHAT_IDENTITY,
# read absorbs check/log/messages, welcome renamed to status.

load test_helper

@test "task clear: fails on non-existent channel" {
  run chat clear no-such-channel --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}
