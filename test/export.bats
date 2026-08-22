#!/usr/bin/env bats
# Task-level integration tests — exercise actual task scripts via chat() shim
#
# API v2: --as replaces --for/--from, implicit identity via $CHAT_IDENTITY,
# read absorbs check/log/messages, welcome renamed to status.

load test_helper

@test "task export: stdout markdown exports raw channel file" {
  send_message "alice" "hello"
  run chat export test-chat --stdout
  [ "$status" -eq 0 ]
  [[ "$output" == *"# test-chat"* ]]
  [[ "$output" == *"### alice"* ]]
  [[ "$output" == *"hello"* ]]
}

@test "task export: stdout json exports structured messages" {
  send_message "alice" "hello"
  run chat export test-chat --stdout --format json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert data[0]['sender'] == 'alice'
assert data[0]['body'] == 'hello'
"
}

@test "task export: filtered markdown stays markdown" {
  send_message "alice" "hello"
  run chat export test-chat --stdout --after 1970-01-01
  [ "$status" -eq 0 ]
  [[ "$output" == *"# test-chat"* ]]
  [[ "$output" == *"### alice"* ]]
  [[ "$output" == *"hello"* ]]
}

@test "task export: rejects invalid format" {
  run chat export test-chat --stdout --format xml
  [ "$status" -ne 0 ]
  [[ "$output" == *"--format must be md or json"* ]]
}

@test "task export: README documents flags when default precedes help" {
  grep -q 'chat export \[--format <format>\].*\[chat\]' "$CHAT_REPO_ROOT/README.md"
  grep -q '| `--format` | Export format: md or json.*| `md`' "$CHAT_REPO_ROOT/README.md"
  grep -q '| `--stdout` | Print to stdout instead of uploading' "$CHAT_REPO_ROOT/README.md"
}

@test "task export: upload requires blob env" {
  send_message "alice" "hello"
  run chat export test-chat
  [ "$status" -ne 0 ]
  [[ "$output" == *"B2_ALIAS and B2_BUCKET must be set"* ]]
  [[ "$output" == *"--stdout"* ]]
}

@test "task export: upload delegates to blobs put" {
  send_message "alice" "hello"
  _setup_mock_blobs
  export B2_ALIAS=test
  export B2_BUCKET=test-bucket

  run chat export test-chat --key chat/test-chat/manual.md
  [ "$status" -eq 0 ]
  [[ "$output" == "chat/test-chat/manual.md" ]]
  grep -q "put chat/test-chat/manual.md -" "$BLOBS_LOG"
  grep -q "hello" "$BLOBS_STDIN"
}
