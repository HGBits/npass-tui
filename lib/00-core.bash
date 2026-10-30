# Core: terminal state, sanitization, status line. Part of npass-tui.

ESC=$'\033'
RESET=$(tput sgr0 2>/dev/null || printf '')
BOLD=$(tput bold 2>/dev/null || printf '')
REV=$(tput rev 2>/dev/null || printf '')
DIM=$(tput dim 2>/dev/null || printf '')
CYAN=$(tput setaf 6 2>/dev/null || printf '')

SCREEN=identities
CURRENT_ID=''
QUERY=''
# Transient message shown above the shortcut line; shortcuts never live here.
STATUS=''
CURSOR=0
OFFSET=0
IDENTITIES=()
PATHS=()
VISIBLE=()
PREVIEW_LINES=()
PREVIEW_OFFSET=0
OTP_LINES=()
OTP_RETURN=entries
ROWS=24
COLS=80

cleanup() {
    stty "$TTY_STATE" 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    tput sgr0 2>/dev/null || true
    tput clear 2>/dev/null || true
}

install_traps() {
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
}

raw_mode() {
    stty -echo -icanon min 1 time 0
    tput civis 2>/dev/null || true
}

# Return the terminal to its original state for interactive child commands.
cooked_mode() {
    stty "$TTY_STATE"
    tput cnorm 2>/dev/null || true
    tput sgr0 2>/dev/null || true
}

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

term_size() {
    ROWS=$(tput lines 2>/dev/null || printf 24)
    COLS=$(tput cols 2>/dev/null || printf 80)
    (( ROWS >= 8 )) || ROWS=8
    (( COLS >= 32 )) || COLS=32
}
