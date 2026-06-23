#!/usr/bin/env bats
bats_require_minimum_version 1.10.0
# Unit tests for lib/chat.sh core functions

load test_helper
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
