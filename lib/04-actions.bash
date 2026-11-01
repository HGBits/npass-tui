# User actions: each delegates secret handling to the npass CLI.

# What C can copy. "kind|argument|label": pw is the entry password, field passes
# the name to `npass clip FIELD`, otp is `npass otp clip`, all is the whole
# document, other asks for a field name.
COPY_MENU=('pw||Senha' 'field|login|Login' 'field|email|E-mail' 'field|pin|PIN'
           'otp||Código OTP' 'other||Outro campo...' 'all|all|Documento inteiro')

open_copy_menu() {
    COPY_ITEMS=("${COPY_MENU[@]}")
    COPY_CURSOR=0
    COPY_PATH=$1
    COPY_RETURN=$SCREEN
    clip_backend
    SCREEN=copy
}

# CLIP_CMD (clip, or clip-x11 on X11) is chosen when the menu opens.
# The value goes straight from npass to the clipboard: the TUI never sees it,
# and the CLI's output (which could hold it on failure) is not shown.
copy_to_clipboard() {
    local kind=$1 arg=$2 label=$3 path=$4 output rc
    case $kind in
        pw) output=$("$NPASS_BIN" "$CLIP_CMD" "$CURRENT_ID" "$path" 2>&1); rc=$? ;;
        otp) output=$("$NPASS_BIN" otp clip "$CURRENT_ID" "$path" 2>&1); rc=$? ;;
        *) output=$("$NPASS_BIN" "$CLIP_CMD" "$arg" "$CURRENT_ID" "$path" 2>&1); rc=$? ;;
    esac
    output=''
    if (( rc == 0 )); then
        set_status "Copiado: $label de $path"
    elif [[ $CLIP_NOTE == 'X11 sem a extensão clip-x11' && $kind != otp ]]; then
        set_status "Falha ao copiar (código $rc). Em X11 instale a extensão clip-x11."
    elif [[ $CLIP_NOTE == 'clip-x11 recusada pelo npass' && $kind != otp ]]; then
        set_status "Falha ao copiar (código $rc). A extensão clip-x11 foi recusada pelo npass (veja X)."
    else
        set_status "Falha ao copiar (código $rc)."
    fi
}

# Enter in the copy menu.
copy_selected() {
    local item=${COPY_ITEMS[COPY_CURSOR]} kind arg label rest
    kind=${item%%|*}
    rest=${item#*|}
    arg=${rest%%|*}
    label=${rest#*|}
    SCREEN=$COPY_RETURN
    if [[ $kind == other ]]; then
        prompt_line 'Nome do campo (vazio cancela): '
        arg=$REPLY
        if [[ -z $arg ]]; then
            set_status 'Cópia cancelada.'
            return
        fi
        # The name becomes an argument of npass: no leading dash, no odd characters.
        if [[ ! $arg =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]]; then
            set_status 'Nome de campo inválido.'
            return
        fi
        label=$arg
    fi
    copy_to_clipboard "$kind" "$arg" "$label" "$COPY_PATH"
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
    PREVIEW_REVEAL=0
}

# Drop the decrypted content as soon as the preview is left. (Bash cannot
# promise the memory is wiped; this only stops the TUI from holding on to it.)
close_preview() {
    SCREEN=entries
    PREVIEW_LINES=()
    PREVIEW_OFFSET=0
    PREVIEW_REVEAL=0
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
    local action=$1 path=$2 rc keep=${VISIBLE[CURSOR]-} idx=$CURSOR
    [[ $action == insert ]] && keep=$path
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
    if load_paths; then restore_selection "$keep" "$idx"; fi
}
