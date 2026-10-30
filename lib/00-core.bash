# Core: terminal state, sanitization, status line. Part of npass-tui.

ESC=$'\033'
RESET=$(tput sgr0 2>/dev/null || printf '')
BOLD=$(tput bold 2>/dev/null || printf '')
REV=$(tput rev 2>/dev/null || printf '')
DIM=$(tput dim 2>/dev/null || printf '')
CLEAR=$(tput clear 2>/dev/null || printf '')
EL=$(tput el 2>/dev/null || printf '')
CIVIS=$(tput civis 2>/dev/null || printf '')
CNORM=$(tput cnorm 2>/dev/null || printf '')
RMAM=$(tput rmam 2>/dev/null || printf '')   # autowrap off while the TUI draws
SMAM=$(tput smam 2>/dev/null || printf '')
WINCH=0
SPACES=''
HRULE=''
FOOTER_TEXT=''

SCREEN=identities
CURRENT_ID=''
QUERY=''
# Transient message shown above the shortcut line; shortcuts never live here.
STATUS=''
CURSOR=0
OFFSET=0
IDENTITIES=()
IDENT_INFO=()        # "N senhas" as reported by `npass identities`, same index as IDENTITIES
IDENT_CURSOR=0       # where the identity list was when an identity was opened
IDENT_OFFSET=0
PATHS=()
VISIBLE=()
PREVIEW_LINES=()
PREVIEW_OFFSET=0
PREVIEW_REVEAL=0     # 1 only after an explicit V; the content is never drawn while 0
OTP_LINES=()
OTP_RETURN=entries
ROWS=24
COLS=80

cleanup() {
    stty "$TTY_STATE" 2>/dev/null || true
    printf '%s%s%s%s' "$CNORM" "$SMAM" "$RESET" "$CLEAR"
}

install_traps() {
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    trap 'WINCH=1' WINCH
}

# TUI mode: no echo, cursor hidden, autowrap off. Whatever ran in cooked mode
# may have scribbled on the screen, so the next frame is a full repaint.
raw_mode() {
    stty -echo -icanon min 1 time 0
    printf '%s%s' "$CIVIS" "$RMAM"
    R_FULL=1
}

# Return the terminal to its original state for interactive child commands.
cooked_mode() {
    stty "$TTY_STATE"
    printf '%s%s%s' "$CNORM" "$SMAM" "$RESET"
}

# Unicode borders when the locale is UTF-8; plain ASCII otherwise.
# NPASS_TUI_ASCII=1 forces ASCII.
detect_unicode() {
    [[ ${NPASS_TUI_ASCII:-0} == 1 ]] && return 1
    case ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} in
        *[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*) return 0 ;;
    esac
    return 1
}

setup_glyphs() {
    if detect_unicode; then
        G_H='─' G_V='│' G_TD='┬' G_TU='┴' G_ELL='…' G_UPDN='↑↓'
    else
        G_H='-' G_V='|' G_TD='+' G_TU='+' G_ELL='~' G_UPDN='Up/Dn'
    fi
}
setup_glyphs

sanitize_text() {
    # Strip terminal escape sequences and control characters from untrusted text.
    printf '%s' "$1" | LC_ALL=C sed -E \
        's#\x1B\][^\x07]*(\x07|\x1B\\)##g; s#\x1B\[[0-?]*[ -/]*[@-~]##g; s#\x1B[@-_]##g; s#[[:cntrl:]]##g'
}

set_status() {
    local clean
    clean=$(sanitize_text "$1")
    STATUS=$clean
}

# Terminal size from the tty on stdin (tput would read a pipe inside $(...)).
term_size() {
    local size
    if size=$(stty size 2>/dev/null) && [[ $size =~ ^([0-9]+)\ ([0-9]+)$ ]]; then
        ROWS=${BASH_REMATCH[1]}
        COLS=${BASH_REMATCH[2]}
    else
        ROWS=$(tput lines 2>/dev/null || printf 24)
        COLS=$(tput cols 2>/dev/null || printf 80)
    fi
    (( ROWS > 0 )) || ROWS=24
    (( COLS > 0 )) || COLS=80
    printf -v SPACES '%*s' "$COLS" ''
    HRULE=${SPACES// /$G_H}
}
