#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

write_passing_test() {
  local path="$1" name="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' \
    '#!/usr/bin/env bats' \
    "@test \"$name\" {" \
    '  true' \
    '}' > "$path"
}

@test "options-only calls use the configured default test directory" {
  run chat test --jobs 1 --filter '^task status: shows chat name$'

  [ "$status" -eq 0 ]
  [[ "$output" == *'1..1'* ]]
  [[ "$output" == *'ok 1 task status: shows chat name'* ]]
}

@test "an explicit test target takes precedence over the configured default" {
  local target="$BATS_TEST_TMPDIR/explicit.bats"
  write_passing_test "$target" 'explicit target only'

  run chat test --jobs 1 "$target"

  [ "$status" -eq 0 ]
  [[ "$output" == *'1..1'* ]]
  [[ "$output" == *'ok 1 explicit target only'* ]]
}

@test "relative test targets resolve from the repository root" {
  run chat test --jobs 1 test/status.bats --filter '^task status: shows chat name$'

  [ "$status" -eq 0 ]
  [[ "$output" == *'1..1'* ]]
  [[ "$output" == *'ok 1 task status: shows chat name'* ]]
}

@test "whitespace-bearing explicit test targets remain one argument" {
  local target="$BATS_TEST_TMPDIR/explicit target/passing test.bats"
  write_passing_test "$target" 'whitespace target'

  run chat test --jobs 2 "$target"

  [ "$status" -eq 0 ]
  [[ "$output" == *'1..1'* ]]
  [[ "$output" == *'ok 1 whitespace target'* ]]
}

@test "the public test path stays serial by default" {
  local target="$BATS_TEST_TMPDIR/default-jobs.bats"
  cat > "$target" <<'BATS'
#!/usr/bin/env bats

@test "default job count" {
  [ "$BATS_NUMBER_OF_PARALLEL_JOBS" = 1 ]
}
BATS

  run chat test "$target"

  [ "$status" -eq 0 ]
  [[ "$output" == *'ok 1 default job count'* ]]
}

@test "callers can explicitly run separate BATS files concurrently through Rush" {
  local probe_dir="$BATS_TEST_TMPDIR/across-file-probe"
  local barrier_dir="$BATS_TEST_TMPDIR/across-file-barrier"
  mkdir -p "$probe_dir" "$barrier_dir"

  test_keyword='@test'
  {
    printf '%s\n' '#!/usr/bin/env bats'
    printf '%s\n' "$test_keyword \"first worker observes second worker\" {"
    cat <<'BATS'
  touch "$PROBE_DIR/one"
  for _ in {1..50}; do
    [ ! -e "$PROBE_DIR/two" ] || return 0
    sleep 0.05
  done
  false
}
BATS
  } > "$probe_dir/one.bats"

  {
    printf '%s\n' '#!/usr/bin/env bats'
    printf '%s\n' "$test_keyword \"second worker observes first worker\" {"
    cat <<'BATS'
  touch "$PROBE_DIR/two"
  for _ in {1..50}; do
    [ ! -e "$PROBE_DIR/one" ] || return 0
    sleep 0.05
  done
  false
}
BATS
  } > "$probe_dir/two.bats"

  export PROBE_DIR="$barrier_dir"
  run chat test --jobs 2 "$probe_dir"

  [ "$status" -eq 0 ]
}
