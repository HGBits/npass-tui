#!/usr/bin/env bats

setup() {
  ROOT="$(cd -- "$(dirname -- "${BATS_TEST_FILENAME}")/.." && pwd)"
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
  insert|edit) exit "${MOCK_ACTION_EXIT:-0}" ;;
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
        printf '\r'; sleep 0.15
        printf 'e'; sleep 0.15
        printf 'q' ;;
      cancel)
        printf '\r'; sleep 0.15
        printf 'a'; sleep 0.15
        printf '\n'; sleep 0.15
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

@test "cria entrada sem usar force" {
  run run_tui create
  [ "$status" -eq 0 ]
  assert_log_has 'identities'
  assert_log_has 'tree --flat personal'
  assert_log_has 'insert personal new/site'
  ! grep -Eq '^insert .* (-f|--force)( |$)' "$LOG"
}

@test "edita a entrada selecionada" {
  run run_tui edit
  [ "$status" -eq 0 ]
  assert_log_has 'edit personal example/login'
}

@test "caminho vazio cancela a criação" {
  run run_tui cancel
  [ "$status" -eq 0 ]
  ! grep -Eq '^insert ' "$LOG"
}

@test "sanitizador não produz erro de expressão do sed" {
  run run_tui create
  [ "$status" -eq 0 ]
  ! grep -Fq 'sed: -e expression' "$PTY_OUT"
}
