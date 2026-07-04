#!/usr/bin/env bats
# Task-level integration tests — exercise actual task scripts via chat() shim
#
# API v2: --as replaces --for/--from, implicit identity via $CHAT_IDENTITY,
# read absorbs check/log/messages, welcome renamed to status.

load test_helper

# ============================================================================
# read task
# ============================================================================

@test "task read: no new messages exits 0" {
  mark_read "alice"
  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"No new messages"* ]]
}

@test "task read: shows unread messages" {
  mark_read "alice"
  send_message "bob" "hey alice"
  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"hey alice"* ]]
}

@test "task read: advances cursor after reading" {
  mark_read "alice"
  send_message "bob" "msg1"
  run chat read test-chat --as alice
  [ "$status" -eq 0 ]

  # Second read should show no new messages
  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"No new messages"* ]]
}

@test "task read: no channel inferred fails with a clear diagnostic" {
  # No positional channel and no $CHAT_CHANNEL → default is inferred but absent.
  run chat read --as alice
  [ "$status" -ne 0 ]
  [[ "$output" == *"no chat channel"* ]]
}

@test "task read: --peek does not advance cursor" {
  mark_read "alice"
  send_message "bob" "peeked"
  local cursor_before
  cursor_before=$(chat_get_cursor "alice")

  run chat read test-chat --as alice --peek
  [ "$status" -eq 0 ]
  [[ "$output" == *"peeked"* ]]

  local cursor_after
  cursor_after=$(chat_get_cursor "alice")
  [ "$cursor_before" = "$cursor_after" ]
}

@test "task read: --all shows everything" {
  send_message "bob" "visible"
  mark_read "alice"
  send_message "carol" "also visible"
  run chat read test-chat --as alice --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"visible"* ]]
  [[ "$output" == *"also visible"* ]]
}

@test "task read: without --as uses spectator mode (shows all)" {
  send_message "bob" "hello"
  run chat read test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
}

@test "task read: CHAT_IDENTITY env var used when --as omitted" {
  mark_read "alice"
  send_message "bob" "env-identity test"
  CHAT_IDENTITY="alice" run chat read test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"env-identity test"* ]]
}

@test "task read: no chat argument ignores package caller-pwd context" {
  _setup_git_remote "https://github.com/KnickKnackLabs/chat.git"
  chat_resolve "default"
  chat_init
  chat_append "bob" "default-channel message"

  export CHAT_CALLER_PWD="$BATS_TEST_TMPDIR/fakerepo"
  run chat read --as alice --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"default-channel message"* ]]
}

@test "task read: --by filters by sender" {
  mark_read "alice"
  send_message "bob" "from bob"
  send_message "carol" "from carol"
  run chat read test-chat --as alice --by bob
  [ "$status" -eq 0 ]
  [[ "$output" == *"from bob"* ]]
  [[ "$output" != *"from carol"* ]]
}

@test "task read: omitted --by ignores stale usage_by env" {
  send_message "bob" "from bob"
  send_message "carol" "from carol"
  usage_by=bob run chat read test-chat --as alice --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"from bob"* ]]
  [[ "$output" == *"from carol"* ]]
}

@test "task read: --all --last shows last N messages" {
  send_message "alice" "first"
  send_message "bob" "second"
  send_message "carol" "third"
  run chat read test-chat --all --last 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"third"* ]]
  [[ "$output" != *"first"* ]]
}

@test "task read: --last implies --all (shows past cursor)" {
  send_message "alice" "old"
  send_message "bob" "also old"
  mark_read "carol"
  send_message "alice" "new"
  # carol's cursor is past "old" and "also old", but --last 3 should show all 3
  run chat read test-chat --as carol --last 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"old"* ]]
  [[ "$output" == *"also old"* ]]
  [[ "$output" == *"new"* ]]
}

@test "task read: --by implies --all (shows past cursor)" {
  send_message "alice" "before cursor"
  mark_read "bob"
  send_message "alice" "after cursor"
  # bob's cursor is past "before cursor", but --by alice should show both
  run chat read test-chat --as bob --by alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"before cursor"* ]]
  [[ "$output" == *"after cursor"* ]]
}

@test "task read: cursor advances after reading messages" {
  send_message "bob" "setup"
  mark_read "alice"

  local cursor_before
  cursor_before=$(chat_get_cursor "alice")

  send_message "bob" "new"
  run chat read test-chat --as alice
  [ "$status" -eq 0 ]

  local cursor_after
  cursor_after=$(chat_get_cursor "alice")
  [ "$cursor_after" -gt "$cursor_before" ]
}

# ============================================================================
# send task
# ============================================================================

@test "task send: appends message" {
  run chat send --as alice --chat test-chat --msg "hello world"
  [ "$status" -eq 0 ]
  grep -q "hello world" "$CHAT_FILE"
}

@test "task send: message has sender header" {
  run chat send --as alice --chat test-chat --msg "test"
  [ "$status" -eq 0 ]
  grep -q "^### alice" "$CHAT_FILE"
}

@test "task send: confirms with output" {
  run chat send --as alice --chat test-chat --msg "hi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sent to test-chat"* ]]
}

@test "task send: CHAT_IDENTITY env var used when --as omitted" {
  CHAT_IDENTITY="alice" run chat send --chat test-chat --msg "env identity send"
  [ "$status" -eq 0 ]
  grep -q "### alice" "$CHAT_FILE"
  grep -q "env identity send" "$CHAT_FILE"
}

@test "task send: fails without identity" {
  unset CHAT_IDENTITY
  run chat send --chat test-chat --msg "no identity"
  [ "$status" -ne 0 ]
  [[ "$output" == *"identity required"* ]]
}

@test "task send: rejects empty message" {
  run chat send --as alice --chat test-chat --msg ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty"* ]]
}

@test "task send: rejects message over 10 lines" {
  local long_msg
  long_msg=$(printf 'line %s\n' $(seq 1 11))
  run chat send --as alice --chat test-chat --msg "$long_msg"
  [ "$status" -ne 0 ]
  [[ "$output" == *"too long"* ]]
}

@test "task send: allows message at exactly 10 lines" {
  local msg
  msg=$(printf 'line %s\n' $(seq 1 10))
  run chat send --as alice --chat test-chat --msg "$msg"
  [ "$status" -eq 0 ]
}

@test "task send: guard blocks send when unread messages exist" {
  # alice sends first message (cursor stays 0 — new agent, guard skips)
  run chat send --as alice --chat test-chat --msg "first"
  [ "$status" -eq 0 ]

  # alice reads to set cursor > 0
  mark_read "alice"

  # bob sends a message alice hasn't read
  send_message "bob" "unread msg"

  # alice tries to send — guard should block and show the unread message inline
  run chat send --as alice --chat test-chat --msg "blocked"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Aborted: you have 1 unread message(s) in test-chat."* ]]
  [[ "$output" == *"unread msg"* ]]
  [[ "$output" == *"To send anyway, use: chat send --force"* ]]
}

@test "task send: guard preview omits sender's own unread messages" {
  send_message "alice" "setup"
  mark_read "alice"

  send_message "bob" "blocking msg"
  send_message "alice" "own one"
  send_message "alice" "own two"
  send_message "alice" "own three"

  run chat send --as alice --chat test-chat --msg "blocked"
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocking msg"* ]]
  [[ "$output" != *"own one"* ]]
  [[ "$output" != *"own two"* ]]
  [[ "$output" != *"own three"* ]]
}

@test "task send: --force bypasses unread guard" {
  run chat send --as alice --chat test-chat --msg "first"
  [ "$status" -eq 0 ]
  mark_read "alice"
  send_message "bob" "unread"

  run chat send --as alice --chat test-chat --msg "forced" --force
  [ "$status" -eq 0 ]
  grep -q "forced" "$CHAT_FILE"
}

@test "task send: omitted --force ignores stale usage_force env" {
  run chat send --as alice --chat test-chat --msg "first"
  [ "$status" -eq 0 ]
  mark_read "alice"
  send_message "bob" "unread"

  usage_force=true run chat send --as alice --chat test-chat --msg "blocked"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Aborted: you have 1 unread message(s) in test-chat."* ]]
}

@test "task send: new agent (cursor=0) bypasses guard" {
  # bob has never read — cursor is 0
  send_message "carol" "some message"
  # bob should be able to send despite carol's unread message
  run chat send --as bob --chat test-chat --msg "hi from bob"
  [ "$status" -eq 0 ]
}

@test "task send: new agent can send multiple times without reading (cursor=0)" {
  # alice has never read — cursor stays at 0, guard is skipped
  run chat send --as alice --chat test-chat --msg "first msg"
  [ "$status" -eq 0 ]

  # alice sends again — still cursor=0, guard still skipped
  run chat send --as alice --chat test-chat --msg "second msg"
  [ "$status" -eq 0 ]
  grep -q "second msg" "$CHAT_FILE"
}

@test "task send: own unread messages do not trigger guard" {
  # alice sends and reads to set cursor > 0
  send_message "alice" "setup"
  mark_read "alice"

  # alice sends — her own message is now "unread" (cursor didn't advance)
  run chat send --as alice --chat test-chat --msg "first from alice"
  [ "$status" -eq 0 ]

  # alice sends again — guard should NOT block (only own messages are unread)
  run chat send --as alice --chat test-chat --msg "second from alice"
  [ "$status" -eq 0 ]
  grep -q "second from alice" "$CHAT_FILE"
}

@test "task send: does not advance sender cursor" {
  # alice sends, then reads (cursor > 0)
  send_message "alice" "setup"
  mark_read "alice"

  # bob sends a message alice hasn't read
  send_message "bob" "hey alice"

  # alice sends with --force to bypass the guard
  run chat send --as alice --chat test-chat --force --msg "replying without reading"
  [ "$status" -eq 0 ]

  # alice's cursor should NOT have advanced — bob's message is still unread
  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"hey alice"* ]]
}

@test "task send: bare token errors instead of sending" {
  run chat send den
  [ "$status" -ne 0 ]
}

@test "task send: omitted --msg ignores stale usage_msg env" {
  usage_msg="stale inherited message" run chat send --as alice --chat test-chat
  [ "$status" -ne 0 ]
  ! grep -q "stale inherited message" "$CHAT_FILE"
}

# ============================================================================
# sig task
# ============================================================================

@test "task sig: sets and shows signature" {
  run chat sig --as alice "sent from pi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Signature set for alice."* ]]

  run chat sig --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Signature for alice:"* ]]
  [[ "$output" == *"sent from pi"* ]]
}

@test "task sig: send appends signature" {
  run chat sig --as alice "sent from pi"
  [ "$status" -eq 0 ]

  run chat send --as alice --chat test-chat --msg "hello"
  [ "$status" -eq 0 ]
  grep -q "hello" "$CHAT_FILE"
  grep -q '^--$' "$CHAT_FILE"
  grep -q "sent from pi" "$CHAT_FILE"
}

@test "task sig: clear removes signature" {
  run chat sig --as alice "sent from pi"
  [ "$status" -eq 0 ]

  run chat sig --as alice --clear
  [ "$status" -eq 0 ]
  [[ "$output" == *"Signature cleared for alice."* ]]

  run chat send --as alice --chat test-chat --msg "hello"
  [ "$status" -eq 0 ]
  grep -q "hello" "$CHAT_FILE"
  ! grep -q "sent from pi" "$CHAT_FILE"
}

@test "task sig: rejects clear with signature text" {
  run chat sig --as alice --clear "sent from pi"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not both"* ]]
}

@test "task sig: omitted --clear ignores stale usage_clear env" {
  usage_clear=true run chat sig --as alice "sent from pi"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Signature set for alice."* ]]

  run chat sig --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"sent from pi"* ]]
}

# ============================================================================
# export task
# ============================================================================

@test "task export: stdout markdown exports raw channel file" {
  send_message "alice" "hello"
  run chat export test-chat --stdout
  [ "$status" -eq 0 ]
  [[ "$output" == *"# test-chat"* ]]
  [[ "$output" == *"### alice"* ]]
  [[ "$output" == *"hello"* ]]
}

@test "task export: stdout json exports structured messages" {
  send_message "alice" "hello"
  run chat export test-chat --stdout --format json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert data[0]['sender'] == 'alice'
assert data[0]['body'] == 'hello'
"
}

@test "task export: filtered markdown stays markdown" {
  send_message "alice" "hello"
  run chat export test-chat --stdout --after 1970-01-01
  [ "$status" -eq 0 ]
  [[ "$output" == *"# test-chat"* ]]
  [[ "$output" == *"### alice"* ]]
  [[ "$output" == *"hello"* ]]
}

@test "task export: rejects invalid format" {
  run chat export test-chat --stdout --format xml
  [ "$status" -ne 0 ]
  [[ "$output" == *"--format must be md or json"* ]]
}

@test "task export: README documents flags when default precedes help" {
  grep -q 'chat export \[--format <format>\].*\[chat\]' "$CHAT_REPO_ROOT/README.md"
  grep -q '| `--format` | Export format: md or json.*| `md`' "$CHAT_REPO_ROOT/README.md"
  grep -q '| `--stdout` | Print to stdout instead of uploading' "$CHAT_REPO_ROOT/README.md"
}

@test "task export: upload requires blob env" {
  send_message "alice" "hello"
  run chat export test-chat
  [ "$status" -ne 0 ]
  [[ "$output" == *"B2_ALIAS and B2_BUCKET must be set"* ]]
  [[ "$output" == *"--stdout"* ]]
}

@test "task export: upload delegates to blobs put" {
  send_message "alice" "hello"
  _setup_mock_blobs
  export B2_ALIAS=test
  export B2_BUCKET=test-bucket

  run chat export test-chat --key chat/test-chat/manual.md
  [ "$status" -eq 0 ]
  [[ "$output" == "chat/test-chat/manual.md" ]]
  grep -q "put chat/test-chat/manual.md -" "$BLOBS_LOG"
  grep -q "hello" "$BLOBS_STDIN"
}

# ============================================================================
# list task
# ============================================================================

@test "task list --json: outputs valid JSON array" {
  send_message "alice" "hello"
  run chat list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)"
}

@test "task list --json: includes channel name and msg count" {
  send_message "alice" "msg1"
  send_message "bob" "msg2"
  run chat list --json
  [ "$status" -eq 0 ]
  local entry
  entry=$(echo "$output" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
for c in channels:
    if c['name'] == 'test-chat':
        print(c['msgs'])
        break
")
  [ "$entry" = "2" ]
}

@test "task list --json: includes last_sender and last_time" {
  send_message "bob" "latest"
  run chat list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
for c in channels:
    if c['name'] == 'test-chat':
        assert c['last_sender'] == 'bob', f'expected bob, got {c[\"last_sender\"]}'
        assert c['last_time'] != '', 'last_time should not be empty'
        break
"
}

@test "task list --json: empty channel included with --all" {
  # test-chat exists but has no messages (only the header from chat_init)
  run chat list --json --all
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
for c in channels:
    if c['name'] == 'test-chat':
        assert c['msgs'] == 0, f'expected 0 msgs, got {c[\"msgs\"]}'
        assert c['last_sender'] == '', f'expected empty sender, got {c[\"last_sender\"]}'
        break
"
}

@test "task list --json: empty channel excluded by default" {
  # test-chat has no messages — should not appear without --all
  run chat list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
names = [c['name'] for c in channels]
assert 'test-chat' not in names, f'empty channel should be hidden, got: {names}'
"
}

@test "task list: human-readable output has no Lines column" {
  send_message "alice" "hello"
  run chat list
  [ "$status" -eq 0 ]
  # Should NOT contain "Lines" header
  ! [[ "$output" == *"Lines"* ]]
}

@test "task list: last activity shows relative time" {
  send_message "alice" "hello"
  run chat list
  [ "$status" -eq 0 ]
  # Should contain relative time (message was just sent, so "just now")
  [[ "$output" == *"just now"* ]]
}

@test "task list: last activity shows only time, not sender" {
  send_message "alice" "hello"
  run chat list
  [ "$status" -eq 0 ]
  # The Last Active column should NOT contain "alice —"
  ! [[ "$output" =~ alice\ — ]]
}

@test "task list: last activity does not show raw YYYY-MM-DD timestamp" {
  send_message "alice" "hello"
  run chat list
  [ "$status" -eq 0 ]
  local year
  year=$(date +%Y)
  ! [[ "$output" =~ test-chat.*${year}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2} ]]
}

@test "task list --json: last_time is raw timestamp not relative" {
  send_message "alice" "hello"
  run chat list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys, re
channels = json.load(sys.stdin)
for c in channels:
    if c['name'] == 'test-chat':
        assert re.match(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}', c['last_time']), \
            f'expected raw timestamp, got: {c[\"last_time\"]}'
        break
"
}

@test "task list: empty channels hidden by default" {
  # test-chat has no messages — shouldn't appear
  # Create a second chat WITH messages
  chat_resolve "active-chat"
  chat_init
  chat_append "alice" "hello"
  run chat list
  [ "$status" -eq 0 ]
  [[ "$output" == *"active-chat"* ]]
  ! [[ "$output" == *"test-chat"* ]]
}

@test "task list: empty channels shown with --all" {
  run chat list --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-chat"* ]]
}

@test "task list: sorted by most recent activity first" {
  # Create two chats with messages at explicitly different timestamps
  local older_file="$CHAT_DATA_DIR/older-chat.md"
  local newer_file="$CHAT_DATA_DIR/newer-chat.md"
  mkdir -p "$CHAT_DATA_DIR/.cursors/older-chat" "$CHAT_DATA_DIR/.cursors/newer-chat"

  cat > "$older_file" <<'OLDER_CHAT'
# older-chat

---

### alice — 2025-01-01 10:00

old message
OLDER_CHAT

  cat > "$newer_file" <<'NEWER_CHAT'
# newer-chat

---

### bob — 2026-03-25 10:00

new message
NEWER_CHAT

  run chat list
  [ "$status" -eq 0 ]
  # newer-chat should appear before older-chat in the output
  local newer_pos older_pos
  newer_pos=$(echo "$output" | grep -n "newer-chat" | head -1 | cut -d: -f1)
  older_pos=$(echo "$output" | grep -n "older-chat" | head -1 | cut -d: -f1)
  [ -n "$newer_pos" ] && [ -n "$older_pos" ]
  [ "$newer_pos" -lt "$older_pos" ]
}

# ----- Unread column + --unread filter -----

@test "task list: no Unread column when no identity" {
  send_message "alice" "hello"
  run chat list
  [ "$status" -eq 0 ]
  ! [[ "$output" == *"Unread"* ]]
}

@test "task list --as: shows Unread column" {
  send_message "alice" "hello"
  run chat list --as bob
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unread"* ]]
}

@test "task list --as: Unread reflects messages from other agents" {
  send_message "alice" "one"
  send_message "alice" "two"
  run chat list --as bob --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
for c in channels:
    if c['name'] == 'test-chat':
        assert c['unread'] == 2, f'expected 2 unread, got {c[\"unread\"]}'
        break
else:
    raise SystemExit('test-chat not found')
"
}

@test "task list --as: own messages do not count as unread" {
  send_message "alice" "mine"
  run chat list --as alice --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
for c in channels:
    if c['name'] == 'test-chat':
        assert c['unread'] == 0, f'expected 0 unread (own msgs), got {c[\"unread\"]}'
        break
else:
    raise SystemExit('test-chat not found')
"
}

@test "task list --json: no unread field when no identity" {
  send_message "alice" "hello"
  run chat list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
for c in channels:
    if c['name'] == 'test-chat':
        assert 'unread' not in c, f'unread should be omitted when no identity, got: {c}'
        break
"
}

@test "task list --unread: hides channels with zero unread" {
  # test-chat has no unread for alice (she's the sender)
  send_message "alice" "hi"
  # second channel with unread for alice
  chat_resolve "busy-chat"
  chat_init
  chat_append "bob" "urgent"
  run chat list --as alice --unread
  [ "$status" -eq 0 ]
  [[ "$output" == *"busy-chat"* ]]
  ! [[ "$output" == *"test-chat"* ]]
}

@test "task list --unread: errors without identity" {
  send_message "alice" "hello"
  run chat list --unread
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires an identity"* ]]
}

@test "task list: \$CHAT_IDENTITY env var enables Unread column without --as" {
  # Agents commonly export CHAT_IDENTITY at session start rather than
  # passing --as on every call. Exercise that path explicitly.
  send_message "alice" "hello"
  export CHAT_IDENTITY=bob
  run chat list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['name'] == 'test-chat':
        assert 'unread' in c, 'unread field should appear with CHAT_IDENTITY set'
        assert c['unread'] == 1, f'expected 1 unread, got {c[\"unread\"]}'
        break
else:
    raise SystemExit('test-chat not found')
"
}

@test "task list --unread --all: --unread still filters empty channels" {
  # --all would normally include the empty channel; --unread filters it back out
  # because an empty channel has zero unread by definition.
  send_message "alice" "has-content"
  chat_resolve "empty-chat"
  chat_init
  run chat list --as bob --unread --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-chat"* ]]
  ! [[ "$output" == *"empty-chat"* ]]
}

@test "task list --unread --json: JSON path respects the unread filter" {
  send_message "alice" "hi"
  chat_resolve "quiet-chat"
  chat_init
  chat_append "bob" "seen"
  run chat list --as bob --unread --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
names = sorted(c['name'] for c in channels)
assert names == ['test-chat'], f'expected only test-chat, got: {names}'
assert channels[0]['unread'] == 1
"
}

# ============================================================================
# status task (replaces welcome)
# ============================================================================

@test "task status: shows chat name" {
  run chat status test-chat
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-chat"* ]]
}

@test "task status: shows unread count with --as" {
  send_message "bob" "hey"
  run chat status test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unread"* ]]
}

@test "task status: hides unread row when fully read" {
  mark_read "alice"
  run chat status test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" != *"Unread"* ]]
}

@test "task status --json: outputs valid JSON" {
  send_message "alice" "hello"
  run chat status test-chat --as bob --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)"
}

@test "task status --json: includes unread count with --as" {
  send_message "alice" "msg1"
  send_message "alice" "msg2"
  run chat status test-chat --as bob --json
  [ "$status" -eq 0 ]
  local unread
  unread=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['unread'])")
  [ "$unread" = "2" ]
}

@test "task status --json: unread is 0 when fully read" {
  send_message "alice" "hello"
  mark_read "bob"
  run chat status test-chat --as bob --json
  [ "$status" -eq 0 ]
  local unread
  unread=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['unread'])")
  [ "$unread" = "0" ]
}

@test "task status --json: omits unread when no --as" {
  send_message "alice" "hello"
  unset CHAT_IDENTITY
  run chat status test-chat --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert 'unread' not in data, f'unread should not be present without --as, got: {data}'
"
}

@test "task status --json: no human-readable header in output" {
  send_message "alice" "hello"
  run chat status test-chat --as alice --json
  [ "$status" -eq 0 ]
  # First non-empty char should be '{' (JSON object)
  local first_char
  first_char=$(echo "$output" | head -c 1)
  [ "$first_char" = "{" ]
}

# ============================================================================
# cursor:clear task
# ============================================================================

@test "task cursor:clear: resets cursor to 0" {
  send_message "alice" "msg"
  mark_read "bob"
  local cursor
  cursor=$(chat_get_cursor "bob")
  [ "$cursor" -gt 0 ]

  run chat cursor:clear test-chat --as bob
  [ "$status" -eq 0 ]

  cursor=$(chat_get_cursor "bob")
  [ "$cursor" = "0" ]
}

@test "task cursor:clear: messages appear as unread after clear" {
  send_message "alice" "hello"
  mark_read "bob"

  # bob has no unread
  local count
  count=$(chat_count_new "bob")
  [ "$count" = "0" ]

  run chat cursor:clear test-chat --as bob
  [ "$status" -eq 0 ]

  # Now bob should see the message as unread
  count=$(chat_count_new "bob")
  [ "$count" -gt 0 ]
}

@test "task cursor:clear: no-op when cursor doesn't exist" {
  run chat cursor:clear test-chat --as newagent
  [ "$status" -eq 0 ]
  [[ "$output" == *"already at start"* ]]
}

@test "task cursor:clear: requires identity" {
  unset CHAT_IDENTITY
  run chat cursor:clear test-chat
  [ "$status" -ne 0 ]
  [[ "$output" == *"identity required"* ]]
}

@test "task cursor:clear: clears inherited usage env for omitted chat and identity" {
  export CHAT_CHANNEL="test-chat"
  export CHAT_IDENTITY="alice"
  export usage_chat="no-such-channel"
  export usage_as="mallory"

  send_message "bob" "msg"
  mark_read "alice"

  run chat cursor:clear
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cursor cleared for alice on test-chat"* ]]
  [ "$(chat_get_cursor "alice")" = "0" ]
}

# ============================================================================
# cursor:undo task
# ============================================================================

@test "task cursor:undo: restores cursor to pre-read position" {
  send_message "bob" "msg1"
  mark_read "alice"
  local cursor_before
  cursor_before=$(chat_get_cursor "alice")

  send_message "bob" "msg2"
  run chat read test-chat --as alice
  [ "$status" -eq 0 ]

  run chat cursor:undo test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cursor restored"* ]]

  local cursor_after
  cursor_after=$(chat_get_cursor "alice")
  [ "$cursor_after" = "$cursor_before" ]
}

@test "task cursor:undo: second read after undo shows same messages" {
  mark_read "alice"
  send_message "bob" "hello again"

  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello again"* ]]

  run chat cursor:undo test-chat --as alice
  [ "$status" -eq 0 ]

  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello again"* ]]
}

@test "task cursor:undo: no-op when no prior read" {
  run chat cursor:undo test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to undo"* ]]
}

@test "task cursor:undo: no-op after read --peek" {
  mark_read "alice"
  send_message "bob" "peeked"

  run chat read test-chat --as alice --peek
  [ "$status" -eq 0 ]

  run chat cursor:undo test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to undo"* ]]
}

@test "task cursor:undo: no-op read does not clobber previous position" {
  mark_read "alice"
  send_message "bob" "recover me"

  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"recover me"* ]]

  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"No new messages"* ]]

  run chat cursor:undo test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cursor restored"* ]]

  run chat read test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"recover me"* ]]
}

@test "task cursor:undo: second undo is a no-op (one level only)" {
  send_message "bob" "msg"
  mark_read "alice"
  send_message "bob" "msg2"

  run chat read test-chat --as alice
  [ "$status" -eq 0 ]

  run chat cursor:undo test-chat --as alice
  [ "$status" -eq 0 ]

  run chat cursor:undo test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to undo"* ]]
}

@test "task cursor:undo: no-op after cursor:clear" {
  send_message "bob" "msg"
  mark_read "alice"
  send_message "bob" "msg2"

  run chat read test-chat --as alice
  [ "$status" -eq 0 ]

  run chat cursor:clear test-chat --as alice
  [ "$status" -eq 0 ]

  run chat cursor:undo test-chat --as alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to undo"* ]]
}

@test "task cursor:undo: requires identity" {
  unset CHAT_IDENTITY
  run chat cursor:undo test-chat
  [ "$status" -ne 0 ]
  [[ "$output" == *"identity required"* ]]
}

@test "task cursor:undo: clears inherited usage env for omitted chat and identity" {
  export CHAT_CHANNEL="test-chat"
  export CHAT_IDENTITY="alice"
  export usage_chat="no-such-channel"
  export usage_as="mallory"

  mark_read "alice"
  send_message "bob" "recover via env"

  run chat read
  [ "$status" -eq 0 ]
  [[ "$output" == *"recover via env"* ]]

  run chat cursor:undo
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cursor restored for alice on test-chat"* ]]
}

@test "task cursor:undo: help examples use the actual task name" {
  run chat cursor:undo --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"chat cursor:undo --as alice"* ]]
  [[ "$output" != *"chat cursor undo"* ]]
}

# ============================================================================
# wait task
# ============================================================================

@test "task wait: --by gates on sender and prints unseen context" {
  mark_read "alice"
  send_message "bob" "context before gate"
  send_message "or" "gate from or"

  run chat wait test-chat --as alice --by or --timeout 1 --poll 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"context before gate"* ]]
  [[ "$output" == *"gate from or"* ]]
}

@test "task wait: --from is an alias for --by" {
  mark_read "alice"
  send_message "or" "from alias gate"

  run chat wait test-chat --as alice --from or --timeout 1 --poll 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"from alias gate"* ]]
}

@test "task wait: --by times out when sender does not match" {
  mark_read "alice"
  send_message "bob" "not from or"

  run chat wait test-chat --as alice --by or --timeout 1 --poll 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Timed out"* ]]
  [[ "$output" == *"no matching messages"* ]]
}

@test "task wait: --mentioned gates on waiting identity mention" {
  mark_read "alice"
  send_message "bob" "context before mention"
  send_message "or" "hey @alice"

  run chat wait test-chat --as alice --mentioned --timeout 1 --poll 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"context before mention"* ]]
  [[ "$output" == *"hey @alice"* ]]
}

@test "task wait: --mentioned requires identity" {
  unset CHAT_IDENTITY
  run chat wait test-chat --mentioned --timeout 1 --poll 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"--mentioned requires an identity"* ]]
}

@test "task wait: --mention gates on explicit mention" {
  mark_read "alice"
  send_message "bob" "hello @carol"

  run chat wait test-chat --as alice --mention carol --timeout 1 --poll 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello @carol"* ]]
}

@test "task wait: --mentioned does not prefix-match longer identities" {
  mark_read "ann"
  send_message "bob" "hello @anna"

  run chat wait test-chat --as ann --mentioned --timeout 1 --poll 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Timed out"* ]]
}

@test "task wait: --mentioned accepts punctuation-delimited mention" {
  mark_read "ann"
  send_message "bob" "hello @ann, please look"

  run chat wait test-chat --as ann --mentioned --timeout 1 --poll 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello @ann, please look"* ]]
}

# ============================================================================
# tui task
# ============================================================================

_setup_tui_compose_gum() {
  local confirm_status="$1"
  export GUM="$BATS_TEST_TMPDIR/gum"
  export GUM_CONFIRM_STATUS="$confirm_status"
  export GUM_WRITE_COUNT="$BATS_TEST_TMPDIR/gum-write-count"
  cat > "$GUM" <<'GUM_MOCK'
#!/usr/bin/env bash
set -euo pipefail
cmd="$1"
shift
case "$cmd" in
  style)
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--" ]; then
        shift
        break
      fi
      shift
    done
    printf '%s\n' "$*"
    ;;
  write)
    count=0
    if [ -f "$GUM_WRITE_COUNT" ]; then
      count=$(cat "$GUM_WRITE_COUNT")
    fi
    printf '%s\n' "$((count + 1))" > "$GUM_WRITE_COUNT"
    if [ "$count" -eq 0 ]; then
      printf 'draft after room change\n'
      printf 'other-chat\n' > "$CHAT_TUI_STATE_DIR/channel"
      exit 0
    fi
    exit 1
    ;;
  confirm)
    printf 'confirm:%s\n' "$*"
    exit "$GUM_CONFIRM_STATUS"
    ;;
  *)
    printf 'unexpected gum command: %s\n' "$cmd" >&2
    exit 1
    ;;
esac
GUM_MOCK
  chmod +x "$GUM"
}

@test "task tui: --dry-run prepares state without attaching" {
  run chat tui test-chat --as alice --session test-ui --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"prepared chat tui session test-ui"* ]]
  [[ "$output" == *"pane_tasks=tui:rooms,tui:view,tui:compose"* ]]
  [[ "$output" == *"command=zellij attach"* ]]
  [ "$(cat "$CHAT_DATA_DIR/.tui/test-ui/channel")" = "test-chat" ]
  [ "$(cat "$CHAT_DATA_DIR/.tui/test-ui/identity")" = "alice" ]
}

@test "task tui: requires identity" {
  unset CHAT_IDENTITY
  run chat tui test-chat --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"identity required"* ]]
}

@test "task tui: fails on non-existent channel" {
  run chat tui no-such-channel --as alice --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task tui: pane tasks can be evaluated independently" {
  send_message "bob" "pane render"
  run chat tui test-chat --as alice --session test-ui --dry-run
  [ "$status" -eq 0 ]

  export CHAT_TUI_ROOT="$CHAT_REPO_ROOT"
  export CHAT_TUI_STATE_DIR="$CHAT_DATA_DIR/.tui/test-ui"
  export CHAT_TUI_LAST=5
  export CHAT_TUI_POLL=1

  run chat tui:rooms --print
  [ "$status" -eq 0 ]
  [[ "$output" == *"▶ test-chat"* ]]

  run chat tui:view --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"chat:test-chat as:alice"* ]]
  [[ "$output" == *"pane render"* ]]

  run chat tui:compose --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"compose"* ]]
  [[ "$output" == *"test-chat"* ]]
}

@test "task tui: pane tasks do not leak clear errors without TERM" {
  send_message "bob" "pane render"
  run chat tui test-chat --as alice --session test-ui --dry-run
  [ "$status" -eq 0 ]

  export CHAT_TUI_ROOT="$CHAT_REPO_ROOT"
  export CHAT_TUI_STATE_DIR="$CHAT_DATA_DIR/.tui/test-ui"
  export CHAT_TUI_LAST=5
  export CHAT_TUI_POLL=1

  TERM= run chat tui:view --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"pane render"* ]]
  [[ "$output" != *"unknown terminal type"* ]]
  [[ "$output" != *"TERM environment variable not set"* ]]

  TERM= run chat tui:compose --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"compose"* ]]
  [[ "$output" != *"unknown terminal type"* ]]
  [[ "$output" != *"TERM environment variable not set"* ]]
}

@test "task tui: view wraps long chat lines at configured width" {
  long_msg="Why this first: it proves the deploy shape, SMS credentials, routing, family isolation, record layout, and kill/timeout behavior without mixing in model quality."
  send_message "bob" "$long_msg"
  run chat tui test-chat --as alice --session test-ui --wrap-width 72 --dry-run
  [ "$status" -eq 0 ]

  export CHAT_TUI_ROOT="$CHAT_REPO_ROOT"
  export CHAT_TUI_STATE_DIR="$CHAT_DATA_DIR/.tui/test-ui"
  export CHAT_TUI_LAST=5
  export CHAT_TUI_POLL=1
  export CHAT_TUI_WRAP_WIDTH=72

  run chat tui:view --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"wrap width 72"* ]]
  [[ "$output" == *$'routing,\nfamily isolation'* ]]
  [[ "$output" == *"mixing in model quality."* ]]
}

@test "task tui: view justifies prose when requested" {
  long_msg="alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
  send_message "bob" "$long_msg"
  run chat tui test-chat --as alice --session test-ui --wrap-width 40 --justify --dry-run
  [ "$status" -eq 0 ]

  export CHAT_TUI_ROOT="$CHAT_REPO_ROOT"
  export CHAT_TUI_STATE_DIR="$CHAT_DATA_DIR/.tui/test-ui"
  export CHAT_TUI_LAST=5
  export CHAT_TUI_POLL=1
  export CHAT_TUI_WRAP_WIDTH=40
  export CHAT_TUI_JUSTIFY=true

  run chat tui:view --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"justify true"* ]]
  [[ "$output" == *"alpha  beta gamma delta epsilon zeta eta"* ]]
  [[ "$output" == *"theta iota kappa lambda mu"* ]]
}

@test "task tui: view leaves markdown-ish lines ragged while justifying prose" {
  msg=$'- bullet one has enough words to exceed the width significantly\nplain prose after bullet should wrap and justify nicely enough'
  send_message "bob" "$msg"
  run chat tui test-chat --as alice --session test-ui --wrap-width 40 --justify --dry-run
  [ "$status" -eq 0 ]

  export CHAT_TUI_ROOT="$CHAT_REPO_ROOT"
  export CHAT_TUI_STATE_DIR="$CHAT_DATA_DIR/.tui/test-ui"
  export CHAT_TUI_LAST=5
  export CHAT_TUI_POLL=1
  export CHAT_TUI_WRAP_WIDTH=40
  export CHAT_TUI_JUSTIFY=true

  run chat tui:view --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"- bullet one has enough words to exceed the width significantly"* ]]
  [[ "$output" == *"plain prose after bullet should wrap and"* ]]
  [[ "$output" == *"justify nicely enough"* ]]
}

@test "task tui: rejects invalid wrap width" {
  run chat tui test-chat --as alice --wrap-width 0 --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"--wrap-width must be a positive integer"* ]]
}

@test "task tui: compose confirms before sending to changed room" {
  chat_resolve "other-chat"
  chat_init
  run chat tui test-chat --as alice --session test-ui --dry-run
  [ "$status" -eq 0 ]

  export CHAT_TUI_ROOT="$CHAT_REPO_ROOT"
  export CHAT_TUI_STATE_DIR="$CHAT_DATA_DIR/.tui/test-ui"
  _setup_tui_compose_gum 0

  run chat tui:compose
  [ "$status" -eq 0 ]
  [[ "$output" == *"compose target changed while drafting"* ]]
  [[ "$output" == *"confirm:Send to #other-chat as alice instead?"* ]]
  [[ "$output" == *"sent to #other-chat"* ]]

  run chat read other-chat --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"draft after room change"* ]]

  run chat read test-chat --all
  [ "$status" -eq 0 ]
  [[ "$output" != *"draft after room change"* ]]
}

@test "task tui: compose leaves changed-room draft unsent when not confirmed" {
  chat_resolve "other-chat"
  chat_init
  run chat tui test-chat --as alice --session test-ui --dry-run
  [ "$status" -eq 0 ]

  export CHAT_TUI_ROOT="$CHAT_REPO_ROOT"
  export CHAT_TUI_STATE_DIR="$CHAT_DATA_DIR/.tui/test-ui"
  _setup_tui_compose_gum 1

  run chat tui:compose
  [ "$status" -eq 0 ]
  [[ "$output" == *"compose target changed while drafting"* ]]
  [[ "$output" == *"draft not sent"* ]]

  run chat read other-chat --all
  [ "$status" -eq 0 ]
  [[ "$output" != *"draft after room change"* ]]

  run chat read test-chat --all
  [ "$status" -eq 0 ]
  [[ "$output" != *"draft after room change"* ]]
}

@test "task tui: README documents independently runnable pane tasks" {
  grep -q '^### chat tui:rooms$' "$CHAT_REPO_ROOT/README.md"
  grep -q '^### chat tui:view$' "$CHAT_REPO_ROOT/README.md"
  grep -q '^### chat tui:compose$' "$CHAT_REPO_ROOT/README.md"
}

# ============================================================================
# non-existent channel — read-only commands should fail, send should create
# ============================================================================

@test "task read: fails on non-existent channel" {
  run chat read no-such-channel
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task read: does not create file for non-existent channel" {
  run chat read no-such-channel
  [ ! -f "$CHAT_DATA_DIR/no-such-channel.md" ]
}

@test "task status: fails on non-existent channel" {
  run chat status no-such-channel
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task wait: fails on non-existent channel" {
  run chat wait no-such-channel --timeout 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task clear: fails on non-existent channel" {
  run chat clear no-such-channel --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task cursor:clear: fails on non-existent channel" {
  run chat cursor:clear no-such-channel --as alice
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task cursor:undo: fails on non-existent channel" {
  run chat cursor:undo no-such-channel --as alice
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task cursor:clear: help examples use the actual task name" {
  run chat cursor:clear --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"chat cursor:clear --as alice"* ]]
  [[ "$output" != *"chat cursor clear"* ]]
}

@test "task send: creates channel that did not exist" {
  run chat send --as alice --chat brand-new-channel --msg "first message"
  [ "$status" -eq 0 ]
  [ -f "$CHAT_DATA_DIR/brand-new-channel.md" ]
  grep -q "first message" "$CHAT_DATA_DIR/brand-new-channel.md"
}

# ============================================================================
# remove task
# ============================================================================

@test "task remove: deletes channel file and cursor dir" {
  send_message "alice" "hello"
  mark_read "alice"
  [ -f "$CHAT_FILE" ]
  [ -d "$CHAT_CURSOR_DIR" ]

  run chat remove test-chat --yes
  [ "$status" -eq 0 ]
  [ ! -f "$CHAT_FILE" ]
  [ ! -d "$CHAT_CURSOR_DIR" ]
  [[ "$output" == *"Removed"* ]]
}

@test "task remove: fails on non-existent channel" {
  run chat remove no-such-channel --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "task remove: refuses to remove default channel" {
  chat_resolve "default"
  chat_init
  run chat remove default --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot remove the default channel"* ]]
  [ -f "$CHAT_DATA_DIR/default.md" ]
}

@test "task remove: refuses to remove legacy global channel" {
  chat_resolve "global"
  chat_init
  run chat remove global --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot remove the global channel"* ]]
  [ -f "$CHAT_DATA_DIR/global.md" ]
}

@test "task remove: channel no longer appears in list" {
  send_message "alice" "hello"
  run chat list --json
  echo "$output" | python3 -c "
import json, sys
names = [c['name'] for c in json.load(sys.stdin)]
assert 'test-chat' in names, f'expected test-chat in {names}'
"

  run chat remove test-chat --yes
  [ "$status" -eq 0 ]

  run chat list --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
names = [c['name'] for c in json.load(sys.stdin)]
assert 'test-chat' not in names, f'test-chat should be gone, got {names}'
"
}

# ============================================================================
# unread task
# ============================================================================

@test "task unread: zero total exits 0 with no output" {
  mark_read "alice"
  run chat unread --as alice
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "task unread: zero total JSON returns structured response" {
  mark_read "alice"
  run chat unread --as alice --json
  [ "$status" -eq 0 ]
  total=$(echo "$output" | jq '.total')
  [ "$total" -eq 0 ]
  channels=$(echo "$output" | jq '.channels | length')
  [ "$channels" -eq 0 ]
}

@test "task unread: sums across channels" {
  # Create a second channel
  CHAT_NAME="other-chat"
  CHAT_FILE="$CHAT_DATA_DIR/other-chat.md"
  CHAT_CURSOR_DIR="$CHAT_DATA_DIR/.cursors/other-chat"
  chat_init

  # Mark both as read, then send messages
  chat_resolve "test-chat"
  mark_read "alice"
  send_message "bob" "msg1"
  send_message "bob" "msg2"

  chat_resolve "other-chat"
  mark_read "alice"
  send_message "carol" "msg3"

  run chat unread --as alice
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "task unread: excludes own messages" {
  mark_read "alice"
  send_message "alice" "my own message"
  send_message "bob" "from bob"
  run chat unread --as alice
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "task unread: JSON shows per-channel breakdown" {
  # Create a second channel
  CHAT_NAME="other-chat"
  CHAT_FILE="$CHAT_DATA_DIR/other-chat.md"
  CHAT_CURSOR_DIR="$CHAT_DATA_DIR/.cursors/other-chat"
  chat_init

  chat_resolve "test-chat"
  mark_read "alice"
  send_message "bob" "msg1"

  chat_resolve "other-chat"
  mark_read "alice"
  send_message "carol" "msg2"
  send_message "carol" "msg3"

  run chat unread --as alice --json
  [ "$status" -eq 0 ]
  total=$(echo "$output" | jq '.total')
  [ "$total" -eq 3 ]
  test_count=$(echo "$output" | jq '.channels["test-chat"]')
  [ "$test_count" -eq 1 ]
  other_count=$(echo "$output" | jq '.channels["other-chat"]')
  [ "$other_count" -eq 2 ]
}

@test "task unread: no channels exits 0" {
  # Remove all chat files
  rm -f "$CHAT_DATA_DIR"/*.md
  run chat unread --as alice
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
