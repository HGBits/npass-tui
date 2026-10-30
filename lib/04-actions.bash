# User actions: each delegates secret handling to the npass CLI.

run_action() {
    local action=$1 path=$2 output rc line
    case $action in
        clip)
            if output=$("$NPASS_BIN" clip "$CURRENT_ID" "$path" 2>&1); then
                show_message 'Comando npass clip concluído.'
            else
                rc=$?
                show_message "Falha ao copiar (código $rc)."
            fi
            return ;;
        otp)
            if output=$("$NPASS_BIN" otp "$CURRENT_ID" "$path" 2>&1); then
                :
            else
                rc=$?
                show_message "Falha ao obter OTP (código $rc)."
                return
            fi
            OTP_LINES=()
            while IFS= read -r line; do OTP_LINES+=("$line"); done <<< "$output"
            output=''
            # The code lives only in OTP_LINES and on the OTP screen, never in the
            # status line. Any key returns to where the person was (main loop).
            OTP_RETURN=$SCREEN
            SCREEN=otp
            set_status "OTP de $path" ;;
    esac
}

open_preview() {
    local path=$1 content line rc
    if content=$("$NPASS_BIN" show --raw "$CURRENT_ID" "$path" 2>&1); then
        :
    else
        rc=$?
        show_message "Erro ao abrir entrada (código $rc)."
        return
    fi
    PREVIEW_LINES=()
    while IFS= read -r line; do PREVIEW_LINES+=("$line"); done <<< "$content"
    content=''
    SCREEN=preview
    PREVIEW_OFFSET=0
}

# One-line prompt on the status row, in the terminal's normal (cooked) mode.
# The answer is left in REPLY; the next frame repaints everything (raw_mode).
prompt_line() {
    local label=$1 input
    cooked_mode
    cup "$STATUS_ROW" 0
    OUT+=$EL$label
    flush
    IFS= read -r input || input=''
    raw_mode
    REPLY=$input
}

search_prompt() {
    prompt_line 'Filtro (vazio remove): '
    QUERY=$REPLY
    rebuild_visible
    set_status "Filtro aplicado: ${QUERY:-nenhum}"
}

confirm_delete() {
    local path=$1 answer safe_identity safe_path
    cooked_mode
    printf '%s' "$CLEAR"
    # Identity and path originate outside the TUI; never print them raw to the terminal.
    safe_identity=$(sanitize_text "$CURRENT_ID")
    safe_path=$(sanitize_text "$path")
    printf 'EXCLUIR ENTRADA\n\nIdentidade: %s\nCaminho:    %s\n\n' "$safe_identity" "$safe_path"
    printf 'A CLI também pode remover anexos de backup desta entrada.\n'
    printf 'Digite exatamente "sim" para continuar (qualquer outra resposta cancela): '
    IFS= read -r answer || answer=''
    raw_mode
    if [[ $answer == sim ]]; then
        REPLY=$path
        return 0
    fi
    set_status 'Exclusão cancelada.'
    return 1
}

prompt_path() {
    local input
    prompt_line 'Caminho da nova entrada (vazio cancela): '
    input=$REPLY
    if [[ -z $input ]]; then
        set_status 'Criação cancelada.'
        return 1
    fi
    REPLY=$input
}

run_interactive_npass() {
    local action=$1 path=$2 rc
    # npass insert prompts for the secret twice; npass edit launches $EDITOR.
    # Both need the user's normal terminal settings and the real terminal streams.
    cooked_mode
    case $action in
        insert) "$NPASS_BIN" insert "$CURRENT_ID" "$path"; rc=$? ;;
        edit)   "$NPASS_BIN" edit "$CURRENT_ID" "$path"; rc=$? ;;
        rm)     "$NPASS_BIN" rm "$CURRENT_ID" "$path"; rc=$? ;;
        *)      rc=2 ;;
    esac
    raw_mode
    if (( rc == 0 )); then
        case $action in
            insert) set_status "Entrada enviada ao npass: $path" ;;
            edit)   set_status "Edição concluída: $path" ;;
            *)      set_status "Comando npass rm concluído: $path" ;;
        esac
    else
        set_status "npass $action falhou (código $rc): $path"
    fi
    load_paths || true
}
