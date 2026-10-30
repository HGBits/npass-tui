#!/usr/bin/env bash

# Garante um bin/npass-tui atual. bin/ está no .gitignore, então num clone novo
# ele não existe até alguém rodar ./build.sh. Reconstrói também se algum
# lib/*.bash ou o build.sh for mais novo que o binário gerado.
tui_test_build() {
  local stale=0 f
  if [[ ! -x $TUI ]]; then
    stale=1
  else
    for f in "$ROOT"/lib/*.bash "$ROOT/build.sh"; do
      [[ $f -nt $TUI ]] && { stale=1; break; }
    done
  fi
  (( stale )) || return 0
  bash "$ROOT/build.sh" --no-sign >/dev/null
}

setup() {
  ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
  TUI="$ROOT/bin/npass-tui"
  tui_test_build
  TMP="$BATS_TEST_TMPDIR"
  MOCK_NPASS="$TMP/npass"
  LOG="$TMP/argv.log"
  TTY_LOG="$TMP/tty.log"
  PTY_OUT="$TMP/pty.out"

  cat >"$MOCK_NPASS" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >>"$NPASS_LOG"
case "$1" in
  help)
    printf 'npass %s - mock\n' "${MOCK_VERSION:-2.8}"
    ;;
  identities)
    if [[ ${MOCK_IDENTITIES_FAIL:-0} == 1 ]]; then printf 'FAIL-SECRET-SENTINEL\n'; exit 17; fi
    if [[ ${MOCK_IDENTITIES_EMPTY:-0} == 1 ]]; then printf 'Nenhuma identidade em /tmp/npass-test-store.\n'; exit 0; fi
    if [[ ${MOCK_IDENTITY_CONTROL:-0} == 1 ]]; then
      printf 'personal\033]0;PWNED-IDENTITY\007 - 2 senhas\n'
    else
      printf 'personal - 2 senhas\n'
    fi
    ;;
  ls)
    if [[ ${MOCK_LS_FAIL:-0} == 1 ]]; then printf 'FAIL-SECRET-SENTINEL\n'; exit 17; fi
    if [[ ${MOCK_MANY:-0} == 1 ]]; then
      for i in $(seq -w 1 40); do printf 'entry-%s\n' "$i"; done
    elif [[ ${MOCK_PATH_CONTROL:-0} == 1 ]]; then
      printf 'example/login\033]0;PWNED-PATH\007\nsecond/entry\n'
    elif [[ ${MOCK_PATH_SPACES:-0} == 1 ]]; then
      printf 'dir with spaces/login entry\nsecond/entry\n'
    else
      printf 'example/login\nsecond/entry\n'
    fi
    ;;
  insert|edit|rm)
    # Record the two terminal modes interactive commands rely on, rather than
    # the implementation-specific full stty serialization.
    tty_mode=$(stty -a)
    {
      [[ $tty_mode =~ (^|[[:space:]])icanon([[:space:]]|$) ]] && printf 'icanon=1\n' || printf 'icanon=0\n'
      [[ $tty_mode =~ (^|[[:space:]])echo([[:space:]]|$) ]] && printf 'echo=1\n' || printf 'echo=0\n'
    } >>"$NPASS_TTY_LOG"
    [[ ${MOCK_ACTION_NOISE:-0} == 1 ]] && printf 'NOISE-FROM-CLI\n'
    exit "${MOCK_ACTION_EXIT:-0}"
    ;;
  show)
    if [[ ${MOCK_SHOW_FAIL:-0} == 1 ]]; then printf 'FAIL-SECRET-SENTINEL\n'; exit 17; fi
    if [[ ${MOCK_SHOW_CONTROL:-0} == 1 ]]; then
      printf 'safe-line\033]0;PWNED-TITLE\007\033[?9999hstill-safe\n'
    else
      printf '<!-- npass:md1 -->\n## Senha\nnot-a-real-secret\n'
    fi
    ;;
  clip)
    if [[ ${MOCK_CLIP_FAIL:-0} == 1 ]]; then printf 'FAIL-SECRET-SENTINEL\n'; exit 17; fi
    exit 0
    ;;
  otp)
    printf 'OTP-SENTINEL-123456\n'
    if [[ ${MOCK_OTP_FAIL:-0} == 1 ]]; then printf 'FAIL-SECRET-SENTINEL\n'; exit 17; fi
    ;;
  *) printf 'unexpected command: %s\n' "$1" >&2; exit 90 ;;
esac
MOCK
  chmod +x "$MOCK_NPASS"
}

run_tui() {
  local scenario="$1"
  : >"$LOG"
  : >"$TTY_LOG"
  if ! TERM=xterm NPASS_BIN="$MOCK_NPASS" NPASS_LOG="$LOG" NPASS_TTY_LOG="$TTY_LOG" \
    MOCK_SHOW_CONTROL="${MOCK_SHOW_CONTROL:-0}" \
    MOCK_SHOW_FAIL="${MOCK_SHOW_FAIL:-0}" \
    MOCK_IDENTITIES_FAIL="${MOCK_IDENTITIES_FAIL:-0}" \
    MOCK_IDENTITIES_EMPTY="${MOCK_IDENTITIES_EMPTY:-0}" \
    MOCK_IDENTITY_CONTROL="${MOCK_IDENTITY_CONTROL:-0}" \
    MOCK_LS_FAIL="${MOCK_LS_FAIL:-0}" \
    MOCK_PATH_CONTROL="${MOCK_PATH_CONTROL:-0}" \
    MOCK_PATH_SPACES="${MOCK_PATH_SPACES:-0}" \
    MOCK_CLIP_FAIL="${MOCK_CLIP_FAIL:-0}" \
    MOCK_OTP_FAIL="${MOCK_OTP_FAIL:-0}" \
    MOCK_ACTION_EXIT="${MOCK_ACTION_EXIT:-0}" \
    MOCK_VERSION="${MOCK_VERSION:-2.8}" \
    python3 "$ROOT/tests/pty_driver.py" "$scenario" "$TUI" \
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
