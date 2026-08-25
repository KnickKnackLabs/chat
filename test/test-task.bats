#!/usr/bin/env bats

setup() {
  CHAT_REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  BATS_LOG="$BATS_TEST_TMPDIR/bats.log"
  BATS_COMMAND="$BATS_TEST_TMPDIR/bats"
  export BATS_LOG BATS_COMMAND

  cat > "$BATS_COMMAND" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for argument in "$@"; do printf 'arg=%s\n' "$argument"; done > "$BATS_LOG"
SH
  chmod +x "$BATS_COMMAND"
}

@test "public higher-jobs path uses the declared Rush backend" {
  run mise run -C "$CHAT_REPO_ROOT" -q test --jobs 2 messages

  [ "$status" -eq 0 ]
  [[ "$output" == *"BATS parallelism: 2 jobs via rush"* ]]
  grep -Fx "arg=$CHAT_REPO_ROOT/test/messages.bats" "$BATS_LOG"
}
