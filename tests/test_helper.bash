#!/usr/bin/env bash

setup() {
  ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
  TMP="$BATS_TEST_TMPDIR"
  MOCK_NPASS="$TMP/npass"
  LOG="$TMP/argv.log"
  PTY_OUT="$TMP/pty.out"

  cat >"$MOCK_NPASS" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"$NPASS_LOG"
case "$1" in
  identities) printf 'personal - 2 entries\n' ;;
  ls) printf 'example/login\nsecond/entry\n' ;;
  insert|edit|rm) exit "${MOCK_ACTION_EXIT:-0}" ;;
  show)
    if [[ ${MOCK_SHOW_CONTROL:-0} == 1 ]]; then
      printf 'safe-line\033]0;PWNED-TITLE\007\033[?9999hstill-safe\n'
    else
      printf '<!-- npass:md1 -->\n## Senha\nnot-a-real-secret\n'
    fi
    ;;
  clip|otp) exit 0 ;;
  *) printf 'unexpected command: %s\n' "$1" >&2; exit 90 ;;
esac
MOCK
  chmod +x "$MOCK_NPASS"
}

run_tui() {
  local scenario="$1"
  : >"$LOG"
  if ! TERM=xterm NPASS_BIN="$MOCK_NPASS" NPASS_LOG="$LOG" \
    MOCK_SHOW_CONTROL="${MOCK_SHOW_CONTROL:-0}" \
    MOCK_ACTION_EXIT="${MOCK_ACTION_EXIT:-0}" \
    python3 "$ROOT/tests/pty_driver.py" "$scenario" "$ROOT/npass-tui" \
    >"$PTY_OUT" 2>&1; then
    cat "$PTY_OUT" >&2
    return 1
  fi
}

assert_log_has() {
  local expected="$1"
  grep -Fxq -- "$expected" "$LOG"
}

# Bats-style runner that preserves status while printing captured PTY diagnostics
# on failure; otherwise Bats hides the output of its `run` helper.
run_tui_case() {
  run run_tui "$1"
  if (( status != 0 )); then
    printf '%s\n' "$output" >&2
  fi
  return 0
}
