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
    elif [[ ${MOCK_TWO_IDS:-0} == 1 ]]; then
      printf 'personal - 2 senhas\nwork - 1 senha\n'
    else
      printf 'personal - 2 senhas\n'
    fi
    ;;
  ls)
    if [[ ${MOCK_LS_FAIL:-0} == 1 ]]; then printf 'FAIL-SECRET-SENTINEL\n'; exit 17; fi
    if [[ ${MOCK_MANY:-0} == 1 ]]; then
      for i in $(seq -w 1 40); do printf 'entry-%s\n' "$i"; done
    elif [[ ${MOCK_PATH_ACCENT:-0} == 1 ]]; then
      printf 'açãoóéí/configuração-muito-longa-demais-para-caber\nsecond/entry\n'
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
    if [[ ${MOCK_SHOW_LONG:-0} == 1 ]]; then
      for i in $(seq -w 1 60); do printf 'line-%s\n' "$i"; done
    elif [[ ${MOCK_SHOW_CONTROL:-0} == 1 ]]; then
      printf 'safe-line\033]0;PWNED-TITLE\007\033[?9999hstill-safe\n'
    else
      printf '<!-- npass:md1 -->\n## Senha\nnot-a-real-secret\n'
    fi
    ;;
  clip | clip-x11 | wclip)
    if [[ ${MOCK_CLIP_FAIL:-0} == 1 ]]; then printf 'FAIL-SECRET-SENTINEL\n'; exit 17; fi
    exit 0
    ;;
  audit)
    printf 'AUDIT-REPORT\n'
    exit "${MOCK_ACTION_EXIT:-0}"
    ;;
  import)
    printf 'IMPORT-DONE\n'
    exit "${MOCK_ACTION_EXIT:-0}"
    ;;
  otp)
    # `otp clip` copies; plain `otp` (print the code) must never be called by the TUI.
    if [[ $2 == clip ]]; then
      if [[ ${MOCK_OTP_FAIL:-0} == 1 ]]; then printf 'FAIL-SECRET-SENTINEL\n'; exit 17; fi
      exit 0
    fi
    printf 'OTP-SENTINEL-123456\n'
    ;;
  extension)
    if [[ ${MOCK_EXT_FAIL:-0} == 1 ]]; then printf 'FAIL-SECRET-SENTINEL\n'; exit 17; fi
    if [[ ${MOCK_EXT_EMPTY:-0} == 1 ]]; then exit 0; fi
    if [[ ${MOCK_EXT_CONTROL:-0} == 1 ]]; then
      printf 'safe-ext\033]0;PWNED-EXT\007\033[?9999h\n'
      exit 0
    fi
    case ${MOCK_EXT_FORMAT:-} in
      bullets) printf 'Extensões instaladas:\n  • audit — audita senhas\n  ✓ import (v0.1.0)\n'; exit 0 ;;
      ansi) printf '\033[1;32m●\033[0m \033[1maudit\033[0m  0.1.0\n\033[1;32m●\033[0m \033[1mimport\033[0m  0.1.0\n'; exit 0 ;;
      paths) printf '/usr/lib/npass/extensions/npass-audit\n/usr/lib/npass/extensions/npass-import.bash\n'; exit 0 ;;
      table) printf 'NOME      VERSÃO  DESCRIÇÃO\naudit     0.1.0   Audita senhas\nimport    0.1.0   Importa senhas\n'; exit 0 ;;
    esac
    if [[ ${MOCK_EXT_ODD:-0} == 1 ]]; then
      printf 'Instaladas:\nnpass-zzz  1.0\n'
      exit 0
    fi
    if [[ ${MOCK_EXT_NOCLIP:-0} == 1 ]]; then
      printf 'npass-audit  0.1.0\nnpass-import  0.1.0\n'
      exit 0
    fi
    printf 'npass-audit  0.1.0\nnpass-import  0.1.0\nnpass-clip-x11  1.0\nnpass-passkey  1.0\n'
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
