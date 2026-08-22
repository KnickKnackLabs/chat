#!/usr/bin/env bats
# Task-level integration tests — exercise actual task scripts via chat() shim
#
# API v2: --as replaces --for/--from, implicit identity via $CHAT_IDENTITY,
# read absorbs check/log/messages, welcome renamed to status.

load test_helper

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

_setup_tui_zellij() {
  export ZELLIJ="$BATS_TEST_TMPDIR/zellij"
  export ZELLIJ_LOG="$BATS_TEST_TMPDIR/zellij.log"
  export ZELLIJ_SESSIONS="${1:-}"
  export ZELLIJ_LIST_STATUS="${2:-0}"
  export ZELLIJ_LIST_ERROR="${3:-}"
  cat > "$ZELLIJ" <<'ZELLIJ_MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$ZELLIJ_LOG"
if [ "$1" = "list-sessions" ]; then
  [ -z "$ZELLIJ_SESSIONS" ] || printf '%s\n' "$ZELLIJ_SESSIONS"
  [ -z "$ZELLIJ_LIST_ERROR" ] || printf '%s\n' "$ZELLIJ_LIST_ERROR" >&2
  exit "$ZELLIJ_LIST_STATUS"
fi
ZELLIJ_MOCK
  chmod +x "$ZELLIJ"
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

@test "task tui: recreates a session without matching chat install provenance" {
  _setup_tui_zellij "test-ui"
  mkdir -p "$CHAT_DATA_DIR/.tui/test-ui"

  run chat tui test-chat --as alice --session test-ui
  [ "$status" -eq 0 ]
  [[ "$output" == *"recreating stale zellij session test-ui"* ]]
  grep -Fxq "kill-session test-ui" "$ZELLIJ_LOG"
  grep -Fxq "delete-session test-ui" "$ZELLIJ_LOG"
  grep -Fq "attach --create --forget --force-run-commands test-ui" "$ZELLIJ_LOG"
  [ "$(cat "$CHAT_DATA_DIR/.tui/test-ui/root")" = "$CHAT_REPO_ROOT" ]
}

@test "task tui: resumes a session from the current chat install" {
  _setup_tui_zellij "test-ui"
  mkdir -p "$CHAT_DATA_DIR/.tui/test-ui"
  printf '%s\n' "$CHAT_REPO_ROOT" > "$CHAT_DATA_DIR/.tui/test-ui/root"

  run chat tui test-chat --as alice --session test-ui
  [ "$status" -eq 0 ]
  [[ "$output" != *"recreating stale zellij session"* ]]
  ! grep -q "kill-session\|delete-session" "$ZELLIJ_LOG"
  grep -Fq "attach --create --forget --force-run-commands test-ui" "$ZELLIJ_LOG"
}

@test "task tui: fails closed when zellij session inventory fails" {
  _setup_tui_zellij "" 2 "zellij server unavailable"

  run chat tui test-chat --as alice --session test-ui
  [ "$status" -eq 2 ]
  [[ "$output" == *"unable to inspect zellij sessions"* ]]
  [[ "$output" == *"zellij server unavailable"* ]]
  ! grep -q "attach\|kill-session\|delete-session" "$ZELLIJ_LOG"
  [ ! -e "$CHAT_DATA_DIR/.tui/test-ui/root" ]
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
  run chat tui test-chat --as alice --session test-ui --wrap-width 72 --no-justify --no-header-separator --message-padding 0 --dry-run
  [ "$status" -eq 0 ]

  export CHAT_TUI_ROOT="$CHAT_REPO_ROOT"
  export CHAT_TUI_STATE_DIR="$CHAT_DATA_DIR/.tui/test-ui"
  export CHAT_TUI_LAST=5
  export CHAT_TUI_POLL=1
  export CHAT_TUI_WRAP_WIDTH=72
  export CHAT_TUI_JUSTIFY=false
  export CHAT_TUI_HEADER_SEPARATOR=false
  export CHAT_TUI_MESSAGE_PADDING=0

  run chat tui:view --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"wrap width 72"* ]]
  [[ "$output" == *$'routing,\nfamily isolation'* ]]
  [[ "$output" == *"mixing in model quality."* ]]
}

@test "task tui: view justifies prose when requested" {
  long_msg="alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
  send_message "bob" "$long_msg"
  run chat tui test-chat --as alice --session test-ui --wrap-width 40 --justify --justify-style greedy --no-header-separator --message-padding 0 --dry-run
  [ "$status" -eq 0 ]

  export CHAT_TUI_ROOT="$CHAT_REPO_ROOT"
  export CHAT_TUI_STATE_DIR="$CHAT_DATA_DIR/.tui/test-ui"
  export CHAT_TUI_LAST=5
  export CHAT_TUI_POLL=1
  export CHAT_TUI_WRAP_WIDTH=40
  export CHAT_TUI_JUSTIFY=true
  export CHAT_TUI_JUSTIFY_STYLE=greedy
  export CHAT_TUI_HEADER_SEPARATOR=false
  export CHAT_TUI_MESSAGE_PADDING=0

  run chat tui:view --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"justify true"* ]]
  [[ "$output" == *"alpha  beta gamma delta epsilon zeta eta"* ]]
  [[ "$output" == *"theta iota kappa lambda mu"* ]]
}

@test "task tui: view can use balanced justification" {
  long_msg="Restart handback: next c0da work is the NVR headless-ingress slice. Start in \`ricon-family/nvr\` clean at \`c90ff78\`. Implement the smallest first pass: reserved headless/service path reads \`shiv:sms listen --json\`, rejects non-allowlisted senders, maps sender to opaque family/conversation id, and writes private per-conversation event records."
  send_message "bob" "$long_msg"
  run chat tui test-chat --as alice --session test-ui --wrap-width 40 --justify --justify-style balanced --no-header-separator --message-padding 0 --color never --dry-run
  [ "$status" -eq 0 ]

  export CHAT_TUI_ROOT="$CHAT_REPO_ROOT"
  export CHAT_TUI_STATE_DIR="$CHAT_DATA_DIR/.tui/test-ui"
  export CHAT_TUI_LAST=5
  export CHAT_TUI_POLL=1
  export CHAT_TUI_WRAP_WIDTH=40
  export CHAT_TUI_JUSTIFY=true
  export CHAT_TUI_JUSTIFY_STYLE=balanced
  export CHAT_TUI_HEADER_SEPARATOR=false
  export CHAT_TUI_MESSAGE_PADDING=0
  export CHAT_TUI_COLOR=never

  run chat tui:view --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"justify-style balanced"* ]]
  [[ "$output" != *'`shiv:sms listen --json`,        rejects'* ]]
  [[ "$output" == *"path   reads"* ]]
  [[ "$output" == *'`shiv:sms listen --json`,'* ]]
}

@test "task tui: view wraps bullets with hanging indent" {
  msg=$'- bullet one has enough words to exceed the width significantly\nplain prose after bullet should wrap and justify nicely enough'
  send_message "bob" "$msg"
  run chat tui test-chat --as alice --session test-ui --wrap-width 40 --justify --justify-style greedy --no-header-separator --message-padding 0 --dry-run
  [ "$status" -eq 0 ]

  export CHAT_TUI_ROOT="$CHAT_REPO_ROOT"
  export CHAT_TUI_STATE_DIR="$CHAT_DATA_DIR/.tui/test-ui"
  export CHAT_TUI_LAST=5
  export CHAT_TUI_POLL=1
  export CHAT_TUI_WRAP_WIDTH=40
  export CHAT_TUI_JUSTIFY=true
  export CHAT_TUI_JUSTIFY_STYLE=greedy
  export CHAT_TUI_HEADER_SEPARATOR=false
  export CHAT_TUI_MESSAGE_PADDING=0

  run chat tui:view --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"- bullet  one has enough words to exceed"* ]]
  [[ "$output" == *"  the width significantly"* ]]
  [[ "$output" == *"plain prose after bullet should wrap and"* ]]
  [[ "$output" == *"justify nicely enough"* ]]
}

@test "task tui: view wraps numbered items with hanging indent" {
  msg=$'1. first, we need to restart your sessions so you can start using the rewind functionality that brownie recently introduced.\n2. c0da, i would like for you to take the next pass at development while quick fixes chat tui.'
  send_message "bob" "$msg"
  run chat tui test-chat --as alice --session test-ui --wrap-width 60 --no-header-separator --message-padding 0 --color never --dry-run
  [ "$status" -eq 0 ]

  export CHAT_TUI_ROOT="$CHAT_REPO_ROOT"
  export CHAT_TUI_STATE_DIR="$CHAT_DATA_DIR/.tui/test-ui"
  export CHAT_TUI_LAST=5
  export CHAT_TUI_POLL=1
  export CHAT_TUI_WRAP_WIDTH=60
  export CHAT_TUI_HEADER_SEPARATOR=false
  export CHAT_TUI_MESSAGE_PADDING=0
  export CHAT_TUI_COLOR=never

  run chat tui:view --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"1. first,"* ]]
  [[ "$output" == *$'\n   start   using'* ]]
  [[ "$output" == *$'\n   recently introduced.\n\n2. c0da,'* ]]
  [[ "$output" == *$'\n   development while quick fixes chat tui.'* ]]
}

@test "task tui: view can show metadata above a full-width separator" {
  send_message "bob" "card layout"
  run chat tui test-chat --as alice --session test-ui --wrap-width 50 --header-separator --message-padding 0 --dry-run
  [ "$status" -eq 0 ]

  export CHAT_TUI_ROOT="$CHAT_REPO_ROOT"
  export CHAT_TUI_STATE_DIR="$CHAT_DATA_DIR/.tui/test-ui"
  export CHAT_TUI_LAST=5
  export CHAT_TUI_POLL=1
  export CHAT_TUI_WRAP_WIDTH=50
  export CHAT_TUI_HEADER_SEPARATOR=true
  export CHAT_TUI_MESSAGE_PADDING=0
  export CHAT_TUI_COLOR=never

  run chat tui:view --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"header-separator true"* ]]
  [[ "$output" == *"bob"*$'\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\ncard layout'* ]]
}

@test "task tui: view can pad message blocks" {
  long_msg="alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
  send_message "bob" "$long_msg"
  run chat tui test-chat --as alice --session test-ui --wrap-width 42 --no-justify --message-padding 2 --header-separator --dry-run
  [ "$status" -eq 0 ]

  export CHAT_TUI_ROOT="$CHAT_REPO_ROOT"
  export CHAT_TUI_STATE_DIR="$CHAT_DATA_DIR/.tui/test-ui"
  export CHAT_TUI_LAST=5
  export CHAT_TUI_POLL=1
  export CHAT_TUI_WRAP_WIDTH=42
  export CHAT_TUI_JUSTIFY=false
  export CHAT_TUI_MESSAGE_PADDING=2
  export CHAT_TUI_HEADER_SEPARATOR=true
  export CHAT_TUI_COLOR=never

  run chat tui:view --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"message-padding 2"* ]]
  [[ "$output" == *"  bob"* ]]
  [[ "$output" == *$'\n  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n  alpha beta gamma delta epsilon zeta eta\n  theta iota kappa lambda mu'* ]]
}

@test "task tui: view colors metadata, senders, mentions, and inline code when requested" {
  send_message "bob" "hello @alice and @c0da at \`a963f70\`"
  run chat tui test-chat --as alice --session test-ui --color always --dry-run
  [ "$status" -eq 0 ]

  export CHAT_TUI_ROOT="$CHAT_REPO_ROOT"
  export CHAT_TUI_STATE_DIR="$CHAT_DATA_DIR/.tui/test-ui"
  export CHAT_TUI_LAST=5
  export CHAT_TUI_POLL=1
  export CHAT_TUI_WRAP_WIDTH=88
  export CHAT_TUI_COLOR=always

  run chat tui:view --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"color always"* ]]
  [[ "$output" == *$'\033[2m\033[38;5;244m'* ]]
  [[ "$output" == *$'\033[1m\033[38;5;'*"bob"*$'\033[0m'* ]]
  [[ "$output" == *$'\033[1m\033[38;5;'*"@alice"*$'\033[0m'* ]]
  [[ "$output" == *$'\033[38;5;252m'*"hello"* ]]
  [[ "$output" == *$'\033[1m\033[38;5;180m'"a963f70"*$'\033[0m'* ]]
  [[ "$output" != *"\`a963f70\`"* ]]
}

@test "task tui: NO_COLOR disables requested color" {
  send_message "bob" "hello @alice"
  run chat tui test-chat --as alice --session test-ui --color always --dry-run
  [ "$status" -eq 0 ]

  export CHAT_TUI_ROOT="$CHAT_REPO_ROOT"
  export CHAT_TUI_STATE_DIR="$CHAT_DATA_DIR/.tui/test-ui"
  export CHAT_TUI_LAST=5
  export CHAT_TUI_POLL=1
  export CHAT_TUI_COLOR=always

  NO_COLOR=1 run chat tui:view --once
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello @alice"* ]]
  [[ "$output" != *$'\033[1m\033[38;5;'*"@alice"* ]]
}

@test "task tui: rejects invalid wrap width" {
  run chat tui test-chat --as alice --wrap-width 0 --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"--wrap-width must be a positive integer"* ]]
}

@test "task tui: rejects invalid color mode" {
  run chat tui test-chat --as alice --color neon --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"--color must be auto, always, or never"* ]]
}

@test "task tui: rejects invalid justify style" {
  run chat tui test-chat --as alice --justify-style wobbly --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"--justify-style must be greedy or balanced"* ]]
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
