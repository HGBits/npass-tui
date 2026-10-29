# Rendering: every string reaching the terminal goes through put()/sanitize_text.

put() {
    local row=$1 col=$2 text=$3 max=${4:-999}
    text=$(sanitize_text "$text")
    tput cup "$row" "$col" 2>/dev/null || true
    printf '%.*s' "$max" "$text"
}

clear_line() { put "$1" 0 "$(printf '%*s' "$COLS" '')" "$COLS"; }

header() {
    term_size
    tput clear
    printf '%s%s' "$CYAN" "$BOLD"
    put 0 0 " npass-tui  /  ${CURRENT_ID:-identidades}" "$COLS"
    printf '%s' "$RESET"
    put 1 0 "$(printf '%*s' "$COLS" '' | tr ' ' '-')" "$COLS"
}

footer() {
    local row=$((ROWS - 2))
    clear_line "$row"
    printf '%s' "$DIM"
    put "$row" 0 "$STATUS" "$COLS"
    printf '%s' "$RESET"
    clear_line $((ROWS - 1))
    put $((ROWS - 1)) 0 '↑/↓ navegar  Enter abrir  a criar  e editar  d excluir  / filtrar  c copiar  o OTP  Esc voltar  q sair' "$COLS"
}

render_list() {
    local title=$1
    local -n items=$2
    local empty_msg=${3:-}
    local i row available start
    header
    put 2 1 "$title" "$((COLS - 2))"
    available=$((ROWS - 5))
    (( available > 0 )) || available=1
    if (( CURSOR < OFFSET )); then OFFSET=$CURSOR; fi
    if (( CURSOR >= OFFSET + available )); then OFFSET=$((CURSOR - available + 1)); fi
    start=$OFFSET
    for ((i=0; i<available; i++)); do
        row=$((3 + i))
        clear_line "$row"
        if (( start + i < ${#items[@]} )); then
            if (( start + i == CURSOR )); then
                printf '%s' "$REV"
                put "$row" 0 "> ${items[start+i]}" "$COLS"
                printf '%s' "$RESET"
            else
                put "$row" 0 "  ${items[start+i]}" "$COLS"
            fi
        fi
    done
    if (( ${#items[@]} == 0 )) && [[ -n $empty_msg ]]; then
        put 4 2 "$empty_msg" "$((COLS - 3))"
    fi
    footer
}

render_preview() {
    local i row max_lines
    header
    put 2 1 'Conteúdo da entrada' "$((COLS - 2))"
    max_lines=$((ROWS - 5))
    for ((i=0; i<max_lines; i++)); do
        row=$((3 + i))
        clear_line "$row"
        if (( PREVIEW_OFFSET + i < ${#PREVIEW_LINES[@]} )); then
            put "$row" 1 "${PREVIEW_LINES[PREVIEW_OFFSET+i]}" "$((COLS - 2))"
        fi
    done
    footer
}

render_current() {
    local empty
    if [[ $SCREEN == identities ]]; then
        render_list 'Escolha uma identidade' IDENTITIES 'Nenhuma identidade. Crie uma com: npass init'
    elif [[ $SCREEN == entries ]]; then
        if [[ -n $QUERY ]]; then
            empty='Nenhuma entrada corresponde ao filtro. Use / com valor vazio para remover.'
        else
            empty='Identidade sem entradas. Pressione a para criar a primeira.'
        fi
        render_list "Entradas  |  filtro: ${QUERY:-nenhum}" VISIBLE "$empty"
    else
        render_preview
    fi
}

show_message() {
    local message=$1
    set_status "$message"
    render_current
    # Short pause; any key dismisses it but is not forwarded as a command.
    IFS= read -r -s -n 1 -t 2 _ || true
}
