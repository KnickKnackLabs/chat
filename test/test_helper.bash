# test_helper.bash — shared setup for chat BATS tests

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  # BATS_TEST_TMPDIR is unique per test and auto-cleaned by BATS (1.4+)
  export CHAT_DATA_DIR="$BATS_TEST_TMPDIR/chat-data"
  mkdir -p "$CHAT_DATA_DIR"

  source "$REPO_DIR/lib/chat.sh"
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

# Helper: run a task script with isolated env
# Usage: run_task read --for alice --chat test-chat
# Sets usage_* env vars from flags (mimics mise/usage parsing)
run_task() {
  local task="$1"
  shift

  # Parse flags into usage_* env vars (mimics what mise does)
  local -a env_vars=()
  env_vars+=("CHAT_DATA_DIR=$CHAT_DATA_DIR")

  while [ $# -gt 0 ]; do
    case "$1" in
      --for)    env_vars+=("usage_for=$2"); shift 2 ;;
      --from)   env_vars+=("usage_from=$2"); shift 2 ;;
      --chat)   env_vars+=("usage_chat=$2"); shift 2 ;;
      --all)    env_vars+=("usage_all=true"); shift ;;
      --mark-read) env_vars+=("usage_mark_read=true"); shift ;;
      --force)  env_vars+=("usage_force=true"); shift ;;
      --message) env_vars+=("usage_message=$2"); shift 2 ;;
      *)        echo "run_task: unknown flag: $1" >&2; return 1 ;;
    esac
  done

  run env "${env_vars[@]}" bash "$REPO_DIR/.mise/tasks/$task"
}
