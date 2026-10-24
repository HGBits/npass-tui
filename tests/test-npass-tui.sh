#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
MOCK_NPASS="$TMP/npass"
LOG="$TMP/argv.log"

cat >"$MOCK_NPASS" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"$NPASS_LOG"
case "$1" in
  identities) printf 'personal - 2 entries\n' ;;
  tree) printf 'example/login\nsecond/entry\n' ;;
  insert|edit) exit "${MOCK_ACTION_EXIT:-0}" ;;
  show) printf '<!-- npass:md1 -->\n## Senha\nnot-a-real-secret\n' ;;
  clip|otp) exit 0 ;;
  *) printf 'unexpected command: %s\n' "$1" >&2; exit 90 ;;
esac
MOCK
chmod +x "$MOCK_NPASS"

if ! command -v script >/dev/null 2>&1; then
  echo "SKIP: util-linux script(1) is unavailable; PTY tests require it." >&2
  exit 0
fi

run_tui() {
  local scenario=$1
  : >"$LOG"
  {
    case "$scenario" in
      create)
        printf '\\r'; sleep 0.15
        printf 'a'; sleep 0.15
        printf 'new/site\\n'; sleep 0.15
        printf 'q' ;;
      edit)
        printf '\\r'; sleep 0.15
        printf 'e'; sleep 0.15
        printf 'q' ;;
      cancel)
        printf '\\r'; sleep 0.15
        printf 'a'; sleep 0.15
        printf '\\n'; sleep 0.15
        printf 'q' ;;
      *) echo "unknown test scenario: $scenario" >&2; return 2 ;;
    esac
  } | TERM=xterm NPASS_BIN="$MOCK_NPASS" NPASS_LOG="$LOG" \
    script -qefc "env TERM=xterm NPASS_BIN='$MOCK_NPASS' NPASS_LOG='$LOG' '$ROOT/npass-tui'" /dev/null \
    >/dev/null 2>&1
}

assert_log_has() {
  local expected=$1
  if ! grep -Fxq -- "$expected" "$LOG"; then
    printf 'FAIL: expected argv log line: %s\nActual log:\n' "$expected" >&2
    cat "$LOG" >&2
    exit 1
  fi
}

# Create: Enter identity, press a, submit a path, then quit.
run_tui $'\ra\nnew/site\nq'
assert_log_has 'identities'
assert_log_has 'tree --flat personal'
assert_log_has 'insert personal new/site'
if grep -Eq '^insert .* (-f|--force)( |$)' "$LOG"; then
  echo 'FAIL: create unexpectedly used force mode' >&2
  exit 1
fi

# Edit: Enter identity, move to entries, press e, then quit.
run_tui $'\re q'
assert_log_has 'edit personal example/login'

# Empty path cancels creation without calling insert.
run_tui $'\ra\nq'
if grep -Eq '^insert ' "$LOG"; then
  echo 'FAIL: empty path should cancel without invoking insert' >&2
  exit 1
fi

echo 'PASS: npass-tui PTY smoke tests'
