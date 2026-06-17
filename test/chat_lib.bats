#!/usr/bin/env bats
# Unit tests for lib/chat.sh core functions

load test_helper

# ============================================================================
# chat_resolve
# ============================================================================

@test "resolve: explicit name sets CHAT_NAME" {
  chat_resolve "my-chat"
  [ "$CHAT_NAME" = "my-chat" ]
}

@test "resolve: explicit name sets CHAT_FILE" {
  chat_resolve "my-chat"
  [ "$CHAT_FILE" = "$CHAT_DATA_DIR/my-chat.md" ]
}

@test "resolve: explicit name sets CHAT_CURSOR_DIR" {
  chat_resolve "my-chat"
  [ "$CHAT_CURSOR_DIR" = "$CHAT_DATA_DIR/.cursors/my-chat" ]
}

@test "resolve: CHAT_CHANNEL env var takes priority over default" {
  CHAT_CHANNEL="from-env" chat_resolve ""
  [ "$CHAT_NAME" = "from-env" ]
}

@test "resolve: explicit name takes priority over CHAT_CHANNEL" {
  CHAT_CHANNEL="from-env" chat_resolve "explicit"
  [ "$CHAT_NAME" = "explicit" ]
}

@test "resolve: empty name falls back to default" {
  chat_resolve ""
  [ "$CHAT_NAME" = "default" ]
}

@test "resolve: package caller-pwd context is ignored when no chat/channel is set" {
  _setup_git_remote "https://github.com/ricon-family/fold.git"
  CHAT_CALLER_PWD="$BATS_TEST_TMPDIR/fakerepo" chat_resolve ""
  [ "$CHAT_NAME" = "default" ]
}

@test "resolve: explicit name sets CHAT_NAME_SOURCE=explicit" {
  chat_resolve "my-chat"
  [ "$CHAT_NAME_SOURCE" = "explicit" ]
}

@test "resolve: CHAT_CHANNEL sets CHAT_NAME_SOURCE=env" {
  CHAT_CHANNEL="from-env" chat_resolve ""
  [ "$CHAT_NAME_SOURCE" = "env" ]
}

@test "resolve: empty name sets CHAT_NAME_SOURCE=default" {
  chat_resolve ""
  [ "$CHAT_NAME_SOURCE" = "default" ]
}

# ============================================================================
# chat_require_file
# ============================================================================

@test "require_file: succeeds when the chat file exists" {
  chat_resolve "test-chat"   # created by setup() via chat_init
  run chat_require_file
  [ "$status" -eq 0 ]
}

@test "require_file: named-but-missing channel points at 'create by sending'" {
  chat_resolve "ghost"
  run chat_require_file
  [ "$status" -ne 0 ]
  [[ "$output" == *"chat 'ghost' does not exist"* ]]
  [[ "$output" == *"Create it by sending"* ]]
}

@test "require_file: no inferred channel gives a no-channel diagnostic" {
  chat_resolve ""   # falls back to default, which does not exist
  run chat_require_file
  [ "$status" -ne 0 ]
  [[ "$output" == *"no chat channel specified"* ]]
  [[ "$output" != *"Create it by sending"* ]]
}

@test "message_count: invalid payload after preamble separator fails closed" {
  cat > "$CHAT_FILE" <<'BAD'
# malformed

Shared communication channel.

---
this is not a frontmatter message block
BAD

  run chat_message_count
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid chat file format"* ]]
}

@test "append: invalid existing channel fails without appending" {
  cat > "$CHAT_FILE" <<'BAD'
# malformed

Shared communication channel.

---
this is not a frontmatter message block
BAD
  local before
  before=$(cat "$CHAT_FILE")

  run chat_append "alice" "should not append"
  [ "$status" -ne 0 ]
  [ "$(cat "$CHAT_FILE")" = "$before" ]
}

# ============================================================================
# chat_resolve_identity / chat_require_identity
# ============================================================================

@test "identity: explicit name sets CHAT_IDENTITY" {
  chat_resolve_identity "alice"
  [ "$CHAT_IDENTITY" = "alice" ]
}

@test "identity: CHAT_IDENTITY env var is used when no explicit name" {
  export CHAT_IDENTITY="from-env"
  chat_resolve_identity ""
  [ "$CHAT_IDENTITY" = "from-env" ]
}

@test "identity: explicit name overrides env var" {
  export CHAT_IDENTITY="from-env"
  chat_resolve_identity "explicit"
  [ "$CHAT_IDENTITY" = "explicit" ]
}

@test "identity: empty when neither flag nor env var set" {
  unset CHAT_IDENTITY
  chat_resolve_identity ""
  [ -z "$CHAT_IDENTITY" ]
}

@test "require_identity: fails when no identity available" {
  unset CHAT_IDENTITY
  run chat_require_identity ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"identity required"* ]]
}

@test "require_identity: succeeds with explicit name" {
  run chat_require_identity "alice"
  [ "$status" -eq 0 ]
}

@test "require_identity: succeeds with env var" {
  export CHAT_IDENTITY="alice"
  run chat_require_identity ""
  [ "$status" -eq 0 ]
}

# ============================================================================
# chat_init
# ============================================================================

@test "init: creates chat file" {
  [ -f "$CHAT_FILE" ]
}

@test "init: creates cursor directory" {
  [ -d "$CHAT_CURSOR_DIR" ]
}

@test "init: chat file has header" {
  head -1 "$CHAT_FILE" | grep -q "^# test-chat"
}

@test "init: idempotent — second call doesn't duplicate" {
  local before
  before=$(wc -l < "$CHAT_FILE" | tr -d ' ')
  chat_init
  local after
  after=$(wc -l < "$CHAT_FILE" | tr -d ' ')
  [ "$before" = "$after" ]
}

# ============================================================================
# chat_line_count
# ============================================================================

@test "line_count: returns correct count" {
  local count
  count=$(chat_line_count)
  local expected
  expected=$(wc -l < "$CHAT_FILE" | tr -d ' ')
  [ "$count" = "$expected" ]
}

# ============================================================================
# cursor: get/set
# ============================================================================

@test "cursor: default is 0 for new agent" {
  local cursor
  cursor=$(chat_get_cursor "alice")
  [ "$cursor" = "0" ]
}

@test "cursor: set and get round-trips" {
  chat_set_cursor "alice"
  local cursor
  cursor=$(chat_get_cursor "alice")
  local total
  total=$(chat_message_count)
  [ "$cursor" = "$total" ]
}

@test "cursor: agents have independent cursors" {
  send_message "bob" "first message"
  chat_set_cursor "alice"

  send_message "bob" "second message"
  chat_set_cursor "bob"

  local alice_cursor bob_cursor
  alice_cursor=$(chat_get_cursor "alice")
  bob_cursor=$(chat_get_cursor "bob")
  [ "$alice_cursor" -lt "$bob_cursor" ]
}

@test "cursor: set requires agent name" {
  run chat_set_cursor ""
  [ "$status" -ne 0 ]
}

@test "cursor: set saves .prev when cursor already exists" {
  send_message "bob" "first"
  chat_set_cursor "alice"
  local first_pos
  first_pos=$(chat_get_cursor "alice")

  send_message "bob" "second"
  chat_set_cursor "alice"

  local prev_file="$CHAT_CURSOR_DIR/alice.prev"
  [ -f "$prev_file" ]
  [ "$(cat "$prev_file")" = "$first_pos" ]
}

@test "cursor: set does not create .prev on first advance" {
  chat_set_cursor "alice"
  [ ! -f "$CHAT_CURSOR_DIR/alice.prev" ]
}

@test "cursor: set preserves .prev when cursor does not advance" {
  send_message "bob" "first"
  chat_set_cursor "alice"
  local first_pos
  first_pos=$(chat_get_cursor "alice")

  send_message "bob" "second"
  chat_set_cursor "alice"

  chat_set_cursor "alice"

  local prev_file="$CHAT_CURSOR_DIR/alice.prev"
  [ -f "$prev_file" ]
  [ "$(cat "$prev_file")" = "$first_pos" ]
}

# ============================================================================
# chat_append
# ============================================================================

@test "append: adds message to file" {
  local before
  before=$(chat_line_count)
  send_message "alice" "hello world"
  local after
  after=$(chat_line_count)
  [ "$after" -gt "$before" ]
}

@test "append: message has correct header format" {
  send_message "alice" "test message"
  grep -q "^from: alice$" "$CHAT_FILE"
}

@test "append: message body is preserved" {
  send_message "alice" "exact content here"
  grep -q "exact content here" "$CHAT_FILE"
}

@test "append: multiple messages accumulate" {
  send_message "alice" "msg1"
  send_message "bob" "msg2"
  send_message "alice" "msg3"
  local count
  count=$(grep -c "^from: " "$CHAT_FILE")
  [ "$count" -eq 3 ]
}

@test "append: multiline message preserved" {
  local msg=$'line one\nline two\nline three'
  send_message "alice" "$msg"
  grep -q "line one" "$CHAT_FILE"
  grep -q "line two" "$CHAT_FILE"
  grep -q "line three" "$CHAT_FILE"
}

@test "append: empty body still creates header" {
  send_message "alice" ""
  grep -q "^from: alice$" "$CHAT_FILE"
}

@test "append: sends a message whose body contains frontmatter-like lines" {
  local adversarial_body=$'from: this looks like frontmatter\nid: 9999\nts: 2026-01-01 10:00\n---\nThis line is actually body text with --- in it'
  send_message "alice" "$adversarial_body"

  # Must count as exactly 1 message (not falsely parsed into multiple blocks)
  local count
  count=$(chat_message_count)
  [ "$count" -eq 1 ]

  # The adversarial content must be preserved verbatim in the file
  grep -q "from: this looks like frontmatter" "$CHAT_FILE"
  grep -q "id: 9999" "$CHAT_FILE"
  grep -q "This line is actually body text" "$CHAT_FILE"
}

# ============================================================================
# chat_new_messages
# ============================================================================

@test "new_messages: returns 1 when no new messages" {
  mark_read "alice"
  run chat_new_messages "alice"
  [ "$status" -eq 1 ]
}

@test "new_messages: returns content after cursor" {
  mark_read "alice"
  send_message "bob" "new stuff"
  run chat_new_messages "alice"
  [ "$status" -eq 0 ]
  [[ "$output" == *"new stuff"* ]]
}

@test "new_messages: includes header" {
  mark_read "alice"
  send_message "bob" "hello"
  run chat_new_messages "alice"
  [[ "$output" == *"from: bob"* ]]
}

@test "new_messages: excludes already-read content" {
  send_message "bob" "old message"
  mark_read "alice"
  send_message "carol" "new message"
  run chat_new_messages "alice"
  [[ "$output" == *"new message"* ]]
  [[ "$output" != *"old message"* ]]
}

@test "new_messages: independent readers see different content" {
  send_message "carol" "msg for everyone"
  mark_read "alice"
  send_message "carol" "msg2"

  # alice only sees msg2
  run chat_new_messages "alice"
  [[ "$output" == *"msg2"* ]]
  [[ "$output" != *"msg for everyone"* ]]

  # bob (cursor=0) sees everything from start
  local bob_cursor
  bob_cursor=$(chat_get_cursor "bob")
  [ "$bob_cursor" = "0" ]
}

@test "new_messages: cursor beyond file length returns 1" {
  printf '99999' > "$CHAT_CURSOR_DIR/alice"
  run chat_new_messages "alice"
  [ "$status" -eq 1 ]
}

# ============================================================================
# chat_count_new
# ============================================================================

@test "count_new: 0 when fully read" {
  mark_read "alice"
  local count
  count=$(chat_count_new "alice")
  [ "$count" = "0" ]
}

@test "count_new: counts message blocks correctly" {
  mark_read "alice"
  send_message "bob" "msg1"
  send_message "carol" "msg2"
  send_message "bob" "msg3"
  local count
  count=$(chat_count_new "alice")
  [ "$count" = "3" ]
}

@test "count_new: 0 for new agent with no messages after header" {
  # New agent, cursor=0, but file only has the init header
  # chat_count_new with cursor 0 counts message blocks in the whole file
  # Since init doesn't add any messages, count should be 0
  local count
  count=$(chat_count_new "newbie")
  [ "$count" = "0" ]
}

@test "count_new: repeated calls return same value (no side effects)" {
  mark_read "alice"
  send_message "bob" "persistent"
  local count1 count2
  count1=$(chat_count_new "alice")
  count2=$(chat_count_new "alice")
  [ "$count1" = "$count2" ]
}

@test "count_new: excludes own messages" {
  mark_read "alice"
  send_message "alice" "my own msg"
  send_message "alice" "another of mine"
  local count
  count=$(chat_count_new "alice")
  [ "$count" = "0" ]
}

@test "count_new: counts only others when mixed" {
  mark_read "alice"
  send_message "alice" "mine"
  send_message "bob" "from bob"
  send_message "alice" "mine again"
  local count
  count=$(chat_count_new "alice")
  [ "$count" = "1" ]
}

# ============================================================================
# chat_list
# ============================================================================

@test "list: includes current chat" {
  run chat_list
  [[ "$output" == *"test-chat"* ]]
}

@test "list: includes multiple chats" {
  # Create a second chat
  chat_resolve "other-chat"
  chat_init
  run chat_list
  [[ "$output" == *"test-chat"* ]]
  [[ "$output" == *"other-chat"* ]]
}

# ============================================================================
# chat_timestamp
# ============================================================================

@test "timestamp: matches YYYY-MM-DD HH:MM format" {
  local ts
  ts=$(chat_timestamp)
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]
}

# ============================================================================
# _chat_to_epoch
# ============================================================================

@test "to_epoch: converts timestamp to epoch" {
  local epoch
  epoch=$(_chat_to_epoch "2026-01-01 00:00")
  [ -n "$epoch" ]
  # Should be a number
  [[ "$epoch" =~ ^[0-9]+$ ]]
}

@test "to_epoch: round-trips with chat_timestamp" {
  local ts epoch
  ts=$(chat_timestamp)
  epoch=$(_chat_to_epoch "$ts")
  [ -n "$epoch" ]
  # Should be within 60s of current time
  local now
  now=$(date +%s)
  local diff=$(( now - epoch ))
  [ "$diff" -ge 0 ] && [ "$diff" -lt 60 ]
}

# ============================================================================
# chat_relative_time
# ============================================================================

@test "relative_time: just now for <60s" {
  local ts
  ts=$(chat_timestamp)
  local result
  result=$(chat_relative_time "$ts")
  [ "$result" = "just now" ]
}

@test "relative_time: minutes ago" {
  # Compute a timestamp 5 minutes in the past
  local epoch_past
  epoch_past=$(( $(date +%s) - 300 ))
  local ts
  if date --version &>/dev/null 2>&1; then
    ts=$(date -d "@$epoch_past" "+%Y-%m-%d %H:%M")
  else
    ts=$(date -r "$epoch_past" "+%Y-%m-%d %H:%M")
  fi
  local result
  result=$(chat_relative_time "$ts")
  [[ "$result" =~ ^[0-9]+m\ ago$ ]]
}

@test "relative_time: hours ago" {
  local epoch_past
  epoch_past=$(( $(date +%s) - 7200 ))
  local ts
  if date --version &>/dev/null 2>&1; then
    ts=$(date -d "@$epoch_past" "+%Y-%m-%d %H:%M")
  else
    ts=$(date -r "$epoch_past" "+%Y-%m-%d %H:%M")
  fi
  local result
  result=$(chat_relative_time "$ts")
  [[ "$result" =~ ^[0-9]+h\ ago$ ]]
}

@test "relative_time: days ago" {
  local epoch_past
  epoch_past=$(( $(date +%s) - 259200 ))  # 3 days
  local ts
  if date --version &>/dev/null 2>&1; then
    ts=$(date -d "@$epoch_past" "+%Y-%m-%d %H:%M")
  else
    ts=$(date -r "$epoch_past" "+%Y-%m-%d %H:%M")
  fi
  local result
  result=$(chat_relative_time "$ts")
  [[ "$result" =~ ^[0-9]+d\ ago$ ]]
}

@test "relative_time: weeks ago" {
  local epoch_past
  epoch_past=$(( $(date +%s) - 1209600 ))  # 14 days
  local ts
  if date --version &>/dev/null 2>&1; then
    ts=$(date -d "@$epoch_past" "+%Y-%m-%d %H:%M")
  else
    ts=$(date -r "$epoch_past" "+%Y-%m-%d %H:%M")
  fi
  local result
  result=$(chat_relative_time "$ts")
  [[ "$result" =~ ^[0-9]+w\ ago$ ]]
}

@test "relative_time: falls back to raw timestamp for very old dates" {
  local result
  result=$(chat_relative_time "2020-01-01 00:00")
  [ "$result" = "2020-01-01 00:00" ]
}

@test "relative_time: empty input returns nothing" {
  local result
  result=$(chat_relative_time "")
  [ -z "$result" ]
}

# ============================================================================
# _chat_trim_trailing_newlines
# ============================================================================

@test "trim: removes trailing newlines" {
  local result
  result=$(_chat_trim_trailing_newlines $'hello\n\n\n')
  [ "$result" = "hello" ]
}

@test "trim: preserves internal newlines" {
  local result
  result=$(_chat_trim_trailing_newlines $'line1\nline2\n')
  [ "$result" = $'line1\nline2' ]
}

@test "trim: handles no trailing newline" {
  local result
  result=$(_chat_trim_trailing_newlines "clean")
  [ "$result" = "clean" ]
}

@test "trim: handles empty string" {
  local result
  result=$(_chat_trim_trailing_newlines "")
  [ "$result" = "" ]
}
