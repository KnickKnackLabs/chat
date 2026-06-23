setup_suite() {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_DIR

  bats_libexec="${BATS_LIBEXEC:-}"
  eval "$(cd "$REPO_DIR" && mise env)"
  [ -z "$bats_libexec" ] || export PATH="$bats_libexec:$PATH"
}