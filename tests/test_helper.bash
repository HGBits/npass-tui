#!/usr/bin/env bash

setup() {
  ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
  TMP="$(mktemp -d)"
  MOCK_NPASS="$TMP/npass"
  LOG="$TMP/argv.log"
  PTY_OUT="$TMP/pty.out"

  cat >"$MOCK_NPASS" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"$NPASS_LOG"
case "$1" in
  identities) printf 'personal - 2 entries\n' ;;
  tree) printf 'example/login\nsecond/entry\n' ;;
  insert|edit|rm) exit "${MOCK_ACTION_EXIT:-0}" ;;
  show) printf '<!-- npass:md1 -->\n## Senha\nnot-a-real-secret\n' ;;
  clip|otp) exit 0 ;;
  *) printf 'unexpected command: %s\n' "$1" >&2; exit 90 ;;
esac
MOCK
  chmod +x "$MOCK_NPASS"
}

teardown() {
  rm -rf "$TMP"
}

run_tui() {
  local scenario="$1"
  : >"$LOG"
  {
    case "$scenario" in
      create)
        printf '\r'; sleep 0.15
        printf 'a'; sleep 0.15
        printf 'new/site\n'; sleep 0.15
        printf 'q' ;;
      edit)
        printf '\r'; sleep 0.05
        printf 'e'; sleep 0.15
        printf 'q' ;;
      cancel)
        printf '\r'; sleep 0.05
        printf 'a'; sleep 0.05
        printf '\n'; sleep 0.15
        printf 'q' ;;
      delete)
        printf '\\r'; sleep 0.10
        printf 'd'; sleep 0.10
        printf 'sim\\n'; sleep 0.20
        printf 'q' ;;
      delete-cancel)
        printf '\\r'; sleep 0.10
        printf 'd'; sleep 0.10
        printf 'nao\\n'; sleep 0.20
        printf 'q' ;;
      *) echo "unknown test scenario: $scenario" >&2; return 2 ;;
    esac
  } | TERM=xterm NPASS_BIN="$MOCK_NPASS" NPASS_LOG="$LOG" \
    script -qefc "env TERM=xterm NPASS_BIN='$MOCK_NPASS' NPASS_LOG='$LOG' bash '$ROOT/npass-tui'" /dev/null \
    >"$PTY_OUT" 2>&1

  if grep -Fq 'sed: -e expression' "$PTY_OUT"; then
    echo 'FAIL: sanitizer emitted a sed expression error' >&2
    cat "$PTY_OUT" >&2
    return 1
  fi
}

assert_log_has() {
  local expected="$1"
  grep -Fxq -- "$expected" "$LOG"
}
