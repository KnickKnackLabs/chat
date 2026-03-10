# test_helper.bash — shared setup for chat BATS tests

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  # Isolated data dir per test — no touching real chat data
  export CHAT_DATA_DIR="$BATS_TMPDIR/chat-test-$$-$BATS_TEST_NUMBER"
  mkdir -p "$CHAT_DATA_DIR"

  source "$REPO_DIR/lib/chat.sh"
  chat_resolve "test-chat"
  chat_init
}

teardown() {
  rm -rf "$CHAT_DATA_DIR"
}

# Helper: send a message directly via lib (bypasses mise task overhead)
send_message() {
  local from="$1"
  shift
  local msg="$*"
  chat_append "$from" "$msg"
}

# Helper: advance cursor to current position (mark all as read)
mark_read() {
  local agent="$1"
  chat_set_cursor "$agent"
}
