#!/usr/bin/env bats
# Tests for the migrate task — legacy '### sender — ts' -> frontmatter format

load test_helper

# Write a legacy-format channel file and return via $LEGACY_FILE.
# Layout (1-based line numbers) — message headers land on lines 7, 11, 15:
#   1 # legacy
#   2
#   3 Shared communication channel...
#   4
#   5 ---
#   6
#   7 ### alice — 2025-01-01 10:00
#   8
#   9 first
#  10
#  11 ### bob — 2025-01-01 10:05
#  12
#  13 second
#  14
#  15 ### alice — 2025-01-01 10:10
#  16
#  17 third
_write_legacy() {
  LEGACY_FILE="$CHAT_DATA_DIR/legacy.md"
  cat > "$LEGACY_FILE" <<'EOF'
# legacy

Shared communication channel. Keep messages short.

---

### alice — 2025-01-01 10:00

first

### bob — 2025-01-01 10:05

second

### alice — 2025-01-01 10:10

third
EOF
  mkdir -p "$CHAT_DATA_DIR/.cursors/legacy"
}

@test "migrate: converts legacy headers to frontmatter blocks" {
  _write_legacy
  run chat migrate legacy
  [ "$status" -eq 0 ]
  # No legacy headers remain
  ! grep -q '^### ' "$LEGACY_FILE"
  # Frontmatter fields are present for each message
  [ "$(grep -c '^from: ' "$LEGACY_FILE")" -eq 3 ]
  grep -q '^from: alice$' "$LEGACY_FILE"
  grep -q '^from: bob$' "$LEGACY_FILE"
  grep -q '^ts: 2025-01-01 10:05$' "$LEGACY_FILE"
  # Bodies preserved
  grep -q '^first$' "$LEGACY_FILE"
  grep -q '^third$' "$LEGACY_FILE"
  # Sequential ids assigned
  grep -q '^id: 1$' "$LEGACY_FILE"
  grep -q '^id: 3$' "$LEGACY_FILE"
}

@test "migrate: the migrated file parses with the new reader" {
  _write_legacy
  chat migrate legacy
  run chat read legacy --all --json --id
  [ "$status" -eq 0 ]
  local json
  json=$(echo "$output" | sed -n '/^\[$/,$ p')
  [ "$(echo "$json" | jq 'length')" -eq 3 ]
  echo "$json" | jq -e '.[1].sender == "bob"'
  echo "$json" | jq -e '.[2].body == "third"'
}

@test "migrate: converts a line-number cursor to a message index" {
  _write_legacy
  # Cursor pointed past line 13 (through the 2nd message) -> index 2
  printf '13' > "$CHAT_DATA_DIR/.cursors/legacy/alice"
  run chat migrate legacy
  [ "$status" -eq 0 ]
  [ "$(cat "$CHAT_DATA_DIR/.cursors/legacy/alice")" = "2" ]
}

@test "migrate: a full-read cursor maps to the last message index" {
  _write_legacy
  # Legacy cursor = total line count (everything read)
  local lines
  lines=$(wc -l < "$LEGACY_FILE" | tr -d ' ')
  printf '%s' "$lines" > "$CHAT_DATA_DIR/.cursors/legacy/bob"
  run chat migrate legacy
  [ "$status" -eq 0 ]
  [ "$(cat "$CHAT_DATA_DIR/.cursors/legacy/bob")" = "3" ]
}

@test "migrate: converts .prev cursor backup files too" {
  _write_legacy
  printf '7' > "$CHAT_DATA_DIR/.cursors/legacy/alice.prev"
  run chat migrate legacy
  [ "$status" -eq 0 ]
  # Line 7 is the first message header -> index 1
  [ "$(cat "$CHAT_DATA_DIR/.cursors/legacy/alice.prev")" = "1" ]
}

@test "migrate: --dry-run does not modify files" {
  _write_legacy
  local before
  before=$(cat "$LEGACY_FILE")
  run chat migrate legacy --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]]
  [ "$(cat "$LEGACY_FILE")" = "$before" ]
}

@test "migrate: is idempotent — skips already-migrated files" {
  _write_legacy
  chat migrate legacy
  local after_first
  after_first=$(cat "$LEGACY_FILE")
  run chat migrate legacy
  [ "$status" -eq 0 ]
  [ "$(cat "$LEGACY_FILE")" = "$after_first" ]
}

@test "migrate: round-trips cursor semantics (read after migrate sees only new)" {
  _write_legacy
  # bob had read through message 2 (line 13) in the legacy file
  printf '13' > "$CHAT_DATA_DIR/.cursors/legacy/bob"
  chat migrate legacy
  # Only the 3rd message ("third", from alice) should be unread for bob
  run chat read legacy --as bob
  [ "$status" -eq 0 ]
  [[ "$output" == *"third"* ]]
  [[ "$output" != *"first"* ]]
  [[ "$output" != *"second"* ]]
}
