# test_helper.bash — shared setup for chat BATS tests

export MISE_CONFIG_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  # BATS_TEST_TMPDIR is unique per test and auto-cleaned by BATS (1.4+)
  export CHAT_DATA_DIR="$BATS_TEST_TMPDIR/chat-data"
  mkdir -p "$CHAT_DATA_DIR"

  # Clear env vars that could leak between tests
  unset CHAT_IDENTITY
  unset CHAT_CHANNEL

  source "$MISE_CONFIG_ROOT/lib/chat.sh"
  chat_resolve "test-chat"
  chat_init
}

teardown() {
  rm -rf "$CHAT_DATA_DIR"
}

# Helper: create a fake git repo with a specific remote URL
# Usage: _setup_git_remote "https://github.com/org/repo.git"
# Creates $BATS_TEST_TMPDIR/fakerepo with the given origin remote
_setup_git_remote() {
  local url="$1"
  local repo_dir="$BATS_TEST_TMPDIR/fakerepo"
  rm -rf "$repo_dir"
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q
  git -C "$repo_dir" remote add origin "$url"
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

# Shim: call chat tasks like real CLI usage
# Usage: chat read --as alice --chat test-chat
#        chat list --json
# No `--` separator needed — mise parses task flags via #USAGE specs.
chat() {
  local task="$1"
  shift
  env CHAT_DATA_DIR="$CHAT_DATA_DIR" \
    mise run -C "$MISE_CONFIG_ROOT" -q "$task" "$@"
}
export -f chat
