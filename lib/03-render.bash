# Rendering: every string reaching the terminal goes through put()/sanitize_text.

put() {
    local row=$1 col=$2 text=$3 max=${4:-999}
    text=$(sanitize_text "$text")
    tput cup "$row" "$col" 2>/dev/null || true
    # ${text:0:max} counts characters; printf '%.*s' counts bytes and would cut
    # an accented path in the middle of a multibyte sequence.
    printf '%s' "${text:0:max}"
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

# Shortcut line for the current screen, in FOOTER_TEXT. Items are
# "priority|key|label" in display order; priority 1 survives longest. When the
# terminal is too narrow the separator shrinks first, then the least important
# items are dropped; the line is never cut in the middle of an item.
footer_keys() {
    local -a items=()
    local item rest key label best best_i i sep
    local seps=('   ' '  ')
    case $SCREEN in
        identities) items=('1|↑↓|Navegar' '1|Enter|Abrir' '1|Q|Sair') ;;
        entries) items=('1|↑↓|Navegar' '1|Enter|Abrir' '2|/|Filtrar' '3|A|Criar' '3|E|Editar'
                        '3|D|Excluir' '2|C|Copiar' '2|O|OTP' '1|Esc|Voltar') ;;
        preview) items=('1|↑↓|Rolar' '2|C|Copiar' '2|O|OTP' '1|Esc|Voltar') ;;
        otp) items=('1|Qualquer tecla|Voltar') ;;
    esac
    while :; do
        for sep in "${seps[@]}"; do
            FOOTER_TEXT=''
            for item in "${items[@]}"; do
                rest=${item#*|}
                key=${rest%%|*}
                label=${rest#*|}
                FOOTER_TEXT+=${FOOTER_TEXT:+$sep}"$key $label"
            done
            (( ${#FOOTER_TEXT} <= COLS && ${#items[@]} > 0 )) && return
        done
        (( ${#items[@]} > 1 )) || break
        best=0; best_i=0
        for i in "${!items[@]}"; do
            item=${items[i]}
            (( ${item%%|*} >= best )) && { best=${item%%|*}; best_i=$i; }
        done
        unset 'items[best_i]'
        items=("${items[@]}")
    done
}

footer() {
    local row=$((ROWS - 2))
    clear_line "$row"
    printf '%s' "$DIM"
    put "$row" 0 "$STATUS" "$COLS"
    printf '%s' "$RESET"
    footer_keys
    clear_line $((ROWS - 1))
    put $((ROWS - 1)) 0 "$FOOTER_TEXT" "$COLS"
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
    local i row max_lines title='Conteúdo da entrada' src=PREVIEW_LINES off=$PREVIEW_OFFSET
    [[ $SCREEN == otp ]] && { title='Código OTP'; src=OTP_LINES; off=0; }
    local -n lines=$src
    header
    put 2 1 "$title" "$((COLS - 2))"
    max_lines=$((ROWS - 5))
    for ((i=0; i<max_lines; i++)); do
        row=$((3 + i))
        clear_line "$row"
        if (( off + i < ${#lines[@]} )); then
            put "$row" 1 "${lines[off+i]}" "$((COLS - 2))"
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
