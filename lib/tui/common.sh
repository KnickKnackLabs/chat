#!/usr/bin/env bash

chat_tui_root() {
  if [ -n "${CHAT_TUI_ROOT:-}" ]; then
    printf '%s\n' "$CHAT_TUI_ROOT"
    return 0
  fi
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

# shellcheck source=../chat.sh
source "$(chat_tui_root)/lib/chat.sh"

chat_tui_state_dir() {
  if [ -n "${CHAT_TUI_STATE_DIR:-}" ]; then
    printf '%s\n' "$CHAT_TUI_STATE_DIR"
  else
    printf '%s/.tui/default\n' "$CHAT_DATA_DIR"
  fi
}

chat_tui_ensure_state() {
  mkdir -p "$(chat_tui_state_dir)"
}

chat_tui_state_path() {
  local key="$1"
  printf '%s/%s\n' "$(chat_tui_state_dir)" "$key"
}

chat_tui_read_state() {
  local key="$1"
  local default="$2"
  local path
  path="$(chat_tui_state_path "$key")"
  if [ -s "$path" ]; then
    cat "$path"
  else
    printf '%s\n' "$default"
  fi
}

chat_tui_write_state() {
  local key="$1"
  local value="$2"
  chat_tui_ensure_state
  printf '%s\n' "$value" > "$(chat_tui_state_path "$key")"
}

chat_tui_current_channel() {
  chat_tui_read_state channel "${CHAT_CHANNEL:-default}"
}

chat_tui_current_identity() {
  chat_tui_read_state identity "${CHAT_IDENTITY:-}"
}

chat_tui_clean() {
  local unset_args=()
  local name
  while IFS='=' read -r name _; do
    case "$name" in
      usage_*) unset_args+=("-u" "$name") ;;
    esac
  done < <(env)

  env ${unset_args[@]+"${unset_args[@]}"} mise run -C "$(chat_tui_root)" -q "$@"
}

chat_tui_gum() {
  "${GUM:-gum}" "$@"
}
