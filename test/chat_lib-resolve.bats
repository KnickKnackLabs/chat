#!/usr/bin/env bats
bats_require_minimum_version 1.10.0
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
