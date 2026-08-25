#!/usr/bin/env bats

load test_helper

setup() {
  CHAT_DATA_DIR="$BATS_TEST_TMPDIR/chat-data"
  BATS_LOG="$BATS_TEST_TMPDIR/bats.log"
  BATS_COMMAND="$BATS_TEST_TMPDIR/bats"
  export CHAT_DATA_DIR BATS_LOG BATS_COMMAND

  cat > "$BATS_COMMAND" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for argument in "$@"; do printf 'arg=%s\n' "$argument"; done > "$BATS_LOG"
SH
  chmod +x "$BATS_COMMAND"
}

@test "public higher-jobs path uses the declared Rush backend" {
  run chat test --jobs 2 messages

  [ "$status" -eq 0 ]
  [[ "$output" == *"BATS parallelism: 2 jobs via rush"* ]]
  grep -Fx "arg=$CHAT_REPO_ROOT/test/messages.bats" "$BATS_LOG"
}
