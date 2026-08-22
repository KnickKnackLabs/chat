#!/usr/bin/env bats
# Task-level integration tests — exercise actual task scripts via chat() shim
#
# API v2: --as replaces --for/--from, implicit identity via $CHAT_IDENTITY,
# read absorbs check/log/messages, welcome renamed to status.

bats_require_minimum_version 1.5.0
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

@test "task wait: new relative cursor snapshots current chat without advancing identity" {
  mark_read "alice"
  local identity_cursor
  identity_cursor=$(chat_get_cursor "alice")
  send_message "bob" "existing before independent wait"

  export CHAT_CALLER_PWD="$BATS_TEST_TMPDIR/watcher"
  mkdir -p "$CHAT_CALLER_PWD"

  run chat wait test-chat --as alice --cursor-file watcher.cursor \
    --timeout 1 --poll 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Timed out"* ]]
  [ "$(cat "$CHAT_CALLER_PWD/watcher.cursor")" = "$(chat_line_count)" ]
  [ "$(chat_get_cursor "alice")" = "$identity_cursor" ]
}

@test "task wait: existing independent cursor resumes and advances after wake" {
  mark_read "alice"
  local identity_cursor cursor_file
  identity_cursor=$(chat_get_cursor "alice")
  cursor_file="$BATS_TEST_TMPDIR/watcher.cursor"
  printf '%s' "$(chat_line_count)" > "$cursor_file"
  send_message "bob" "new after independent cursor"

  run chat wait test-chat --as alice --cursor-file "$cursor_file" \
    --timeout 1 --poll 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"new after independent cursor"* ]]
  [ "$(cat "$cursor_file")" = "$(chat_line_count)" ]
  [ "$(chat_get_cursor "alice")" = "$identity_cursor" ]
}

@test "task wait: explicit zero independent cursor includes existing messages" {
  local cursor_file="$BATS_TEST_TMPDIR/watcher.cursor"
  send_message "bob" "existing from cursor zero"
  printf '0' > "$cursor_file"

  run chat wait test-chat --as alice --cursor-file "$cursor_file" \
    --timeout 1 --poll 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"existing from cursor zero"* ]]
  [ "$(cat "$cursor_file")" = "$(chat_line_count)" ]
}

@test "task wait: --json emits one message object per line in order" {
  local cursor_file="$BATS_TEST_TMPDIR/watcher.cursor"
  printf '%s' "$(chat_line_count)" > "$cursor_file"
  send_message "bob" "first JSON message"
  send_message "or" $'second JSON message\nwith another body line'

  run chat wait test-chat --cursor-file "$cursor_file" --json \
    --timeout 1 --poll 1
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
  [[ "$output" != *"Waiting for"* ]]
  [[ "$output" != *"New messages"* ]]

  local first second
  first=$(printf '%s\n' "$output" | sed -n '1p')
  second=$(printf '%s\n' "$output" | sed -n '2p')
  jq -e 'keys == ["body", "sender", "timestamp"]' <<< "$first"
  jq -e '.sender == "bob" and .body == "first JSON message"' <<< "$first"
  jq -e '.timestamp | test("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$")' \
    <<< "$first"
  jq -e '.sender == "or" and .body == "second JSON message\nwith another body line"' \
    <<< "$second"
}

@test "task wait: --json keeps message shape under --loop" {
  local cursor_file="$BATS_TEST_TMPDIR/watcher.cursor"
  printf '%s' "$(chat_line_count)" > "$cursor_file"
  send_message "bob" "looped JSON message"

  run --separate-stderr chat wait test-chat --cursor-file "$cursor_file" \
    --json --loop --timeout 1 --poll 1
  [ "$status" -ne 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  jq -e 'keys == ["body", "sender", "timestamp"]' <<< "$output"
  jq -e '.sender == "bob" and .body == "looped JSON message"' <<< "$output"
  [[ "$output" != *"Waiting for"* ]]
  [[ "$output" != *"New messages"* ]]
  [[ "$stderr" == *"Timed out after 1s"* ]]
}

@test "task wait: independent cursor rejects invalid content" {
  local cursor_file="$BATS_TEST_TMPDIR/watcher.cursor"
  printf 'invalid' > "$cursor_file"

  run chat wait test-chat --cursor-file "$cursor_file" --timeout 1 --poll 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid cursor in $cursor_file"* ]]
}

@test "task wait: independent cursor requires an existing parent" {
  local cursor_file="$BATS_TEST_TMPDIR/missing/watcher.cursor"

  run chat wait test-chat --cursor-file "$cursor_file" --timeout 1 --poll 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"cursor file parent does not exist"* ]]
}

@test "task wait: fails on non-existent channel" {
  run chat wait no-such-channel --timeout 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}
