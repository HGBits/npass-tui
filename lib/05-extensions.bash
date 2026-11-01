# Extensions: optional commands installed next to npass and called as
# `npass NAME ...`. `npass extension list` is the source of truth for what is
# installed. Two things use them:
#   - the copy menu picks the clipboard backend (clip, or clip-x11 on X11);
#   - the Extensions screen (X) runs the ones that have a TUI action.

EXT_NAMES=()      # extension name, as `npass extension list` prints it
EXT_STATE=()      # "ok" or "refused" (the core checked ownership and signature)
EXT_WHY=()        # the core's reason when refused (sem_sig, permissao, ...)
EXT_RAW=()        # the line as the core printed it
EXT_INFO=()       # other lines, e.g. the notice that no extension directory exists
EXT_CURSOR=0
EXT_LOADED=0
EXT_RC=0
CLIP_CMD=clip     # command behind "copy": clip, clip-x11 or wclip
CLIP_NOTE=''      # why, when it is not the default

# Reasons the core gives when it refuses an extension (lib/11-extensions.bash).
declare -A EXT_WHY_TEXT=(
    [sem_sig]='sem o arquivo de assinatura (.sig)'
    [permissao]='dono ou permissões inseguros (precisa ser do root, sem escrita para grupo/outros)'
    [assinatura_invalida]='assinatura inválida'
    [symlink]='é um link simbólico'
    [ausente]='arquivo ausente ou não executável'
    [nome_invalido]='nome inválido'
)

# What the TUI knows about the official extensions (README of npass-extensions).
declare -A EXT_DESC=(
    [audit]='Audita as senhas de uma identidade por vazamentos (HIBP), força e reutilização. Nenhuma senha é impressa.'
    [import]='Importa senhas de outros gerenciadores (Bitwarden, KeePassXC, Firefox, Aegis, ...) para uma identidade.'
    [passkey]='Passkeys (WebAuthn/FIDO2) guardadas só no npass.'
    [clip-x11]='Copia senha ou campo para o clipboard do X11 (xclip).'
    [wclip]='Copia senha ou campo para o clipboard do Windows (wclip).'
)
declare -A EXT_USE=(
    [audit]='Enter audita a identidade selecionada.'
    [import]='Enter importa um arquivo para a identidade selecionada.'
    [passkey]='Sem ação na TUI. Use na CLI: npass extension passkey.'
    [clip-x11]='Enter copia a senha ou um campo da entrada selecionada via xclip (X11).'
    [wclip]='Usada pelo menu Copiar com NPASS_TUI_CLIP=wclip, sem ação aqui.'
)

# Fills the EXT_* arrays from `npass extension list`. The core prints one line
# per extension, "NAME: ok" or "NAME: recusada (MOTIVO)" (the motive is a fixed
# word such as permissao or assinatura_invalida), and a different notice when it
# finds no extension directory. Any other line is kept in EXT_INFO. Returns 1,
# with the exit code in EXT_RC, when the command is not available.
ext_load() {
    local output line
    output=$("$NPASS_BIN" extension list 2>&1) || { EXT_RC=$?; return 1; }
    output=$(sanitize_text "$output")
    EXT_NAMES=() EXT_STATE=() EXT_WHY=() EXT_RAW=() EXT_INFO=()
    while IFS= read -r line; do
        line=${line#"${line%%[![:space:]]*}"}
        [[ -n $line ]] || continue
        if [[ $line =~ ^([a-z0-9][a-z0-9-]*):[[:space:]]+ok$ ]] &&
            [[ ${BASH_REMATCH[1]} != npass-* ]]; then
            EXT_NAMES+=("${BASH_REMATCH[1]}") EXT_STATE+=(ok) EXT_WHY+=('') EXT_RAW+=("$line")
        elif [[ $line =~ ^([a-z0-9][a-z0-9-]*):[[:space:]]+recusada[[:space:]]*\(([a-z_]+)\)$ ]] &&
            [[ ${BASH_REMATCH[1]} != npass-* ]]; then
            EXT_NAMES+=("${BASH_REMATCH[1]}") EXT_STATE+=(refused) EXT_WHY+=("${BASH_REMATCH[2]}") EXT_RAW+=("$line")
        else
            EXT_INFO+=("$line")
        fi
    done <<< "$output"
    EXT_LOADED=1
}

# ext_installed NAME: listed and accepted by the core.
ext_installed() {
    local i
    for i in "${!EXT_NAMES[@]}"; do
        [[ ${EXT_NAMES[i]} == "$1" && ${EXT_STATE[i]} == ok ]] && return 0
    done
    return 1
}

# ext_refused NAME: listed but refused by the core.
ext_refused() {
    local i
    for i in "${!EXT_NAMES[@]}"; do
        [[ ${EXT_NAMES[i]} == "$1" && ${EXT_STATE[i]} == refused ]] && return 0
    done
    return 1
}

session_is_x11() {
    case ${XDG_SESSION_TYPE:-} in
        x11) return 0 ;;
        wayland) return 1 ;;
    esac
    [[ -z ${WAYLAND_DISPLAY:-} && -n ${DISPLAY:-} ]]
}

# Chooses what "copy" calls. NPASS_TUI_CLIP=clip|clip-x11|wclip forces it. On an
# X11 session the core clip (Wayland) does not work, so clip-x11 is used when
# the extension is installed; its command line matches `clip`.
clip_backend() {
    CLIP_CMD=clip CLIP_NOTE=''
    case ${NPASS_TUI_CLIP:-} in
        clip | clip-x11 | wclip)
            CLIP_CMD=$NPASS_TUI_CLIP
            CLIP_NOTE="$CLIP_CMD (NPASS_TUI_CLIP)"
            return ;;
    esac
    session_is_x11 || return 0
    (( EXT_LOADED )) || ext_load || true
    if ext_installed clip-x11; then
        CLIP_CMD=clip-x11
        CLIP_NOTE='clip-x11 (sessão X11)'
    elif ext_refused clip-x11; then
        CLIP_NOTE='clip-x11 recusada pelo npass'
    else
        CLIP_NOTE='X11 sem a extensão clip-x11'
    fi
}

open_extensions() {
    if ! ext_load; then
        set_status "Extensões indisponíveis (código $EXT_RC)."
        return
    fi
    EXT_CURSOR=0
    EXT_RETURN=$SCREEN
    SCREEN=extensions
}

# Identity an extension acts on: the selected one in the identity list, or the
# one that is open.
ext_target_id() {
    if [[ $EXT_RETURN == identities ]]; then
        printf '%s' "${IDENTITIES[CURSOR]-}"
    else
        printf '%s' "$CURRENT_ID"
    fi
}

# Run a npass command in the terminal's normal mode so its own output and
# prompts work, then wait for Enter so the output can be read.
run_external() {
    local rc
    cooked_mode
    printf '%s' "$CLEAR"
    "$NPASS_BIN" "$@"
    rc=$?
    printf '\n[Enter para voltar] '
    IFS= read -r _ || true
    raw_mode
    return $rc
}

# After an extension that writes (import): lists and counts may have changed.
ext_reload() {
    local keep=${VISIBLE[CURSOR]-} idx=$CURSOR off=$OFFSET
    if [[ $EXT_RETURN == identities ]]; then
        load_identities || true
        CURSOR=$idx OFFSET=$off
    elif load_paths; then
        restore_selection "$keep" "$idx"
    fi
}

ext_audit() {
    local id=$1 rc
    prompt_line "Auditar $id [s = HIBP online / o = offline / Enter cancela]: "
    case $REPLY in
        s | S) run_external extension audit "$id"; rc=$? ;;
        o | O) run_external extension audit "$id" --offline; rc=$? ;;
        *) set_status 'Auditoria cancelada.'; return ;;
    esac
    if (( rc == 0 )); then set_status "Auditoria de $id concluída."; else set_status "npass audit falhou (código $rc)."; fi
}

# Copy through the explicit clip-x11 extension action. The entry content
# never enters the TUI: stdout/stderr are captured and discarded, and only the
# exit status is reported. The extension itself owns xclip and clipboard cleanup.
ext_clip_x11() {
    local id=$1 path field label output rc
    if [[ $EXT_RETURN != entries ]]; then
        set_status 'Abra uma entrada antes de usar clip-x11.'
        return
    fi
    path=${VISIBLE[CURSOR]-}
    if [[ -z $path ]]; then
        set_status 'Nenhuma entrada selecionada.'
        return
    fi
    if ! session_is_x11 || [[ -z ${DISPLAY:-} ]]; then
        set_status 'clip-x11 requer uma sessão X11 ativa (DISPLAY).'
        return
    fi
    prompt_line 'Campo (vazio = senha, all = documento inteiro): '
    field=$REPLY
    if [[ -n $field && ! $field =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]]; then
        set_status 'Nome de campo inválido.'
        return
    fi
    label='senha'
    [[ $field == all ]] && label='documento'
    [[ -n $field && $field != all ]] && label="campo $field"
    if [[ -n $field ]]; then
        output=$("$NPASS_BIN" extension clip-x11 "$field" "$id" "$path" 2>&1)
        rc=$?
    else
        output=$("$NPASS_BIN" extension clip-x11 "$id" "$path" 2>&1)
        rc=$?
    fi
    output=''
    if (( rc == 0 )); then
        set_status "Copiado via clip-x11: $label de $path."
    else
        set_status "clip-x11 falhou (código $rc). Verifique X11, xclip e a extensão."
    fi
}

ext_import() {
    local id=$1 format file answer rc
    prompt_line 'Formato (veja: npass import --list): '
    format=$REPLY
    [[ -n $format ]] || { set_status 'Importação cancelada.'; return; }
    if [[ ! $format =~ ^[a-z0-9][a-z0-9_-]{0,31}$ ]]; then
        set_status 'Formato inválido.'
        return
    fi
    prompt_line 'Arquivo de origem: '
    file=$REPLY
    [[ -n $file ]] || { set_status 'Importação cancelada.'; return; }
    [[ $file == '~/'* ]] && file=$HOME/${file#'~/'}
    if [[ $file == -* ]]; then
        set_status 'Caminho de arquivo inválido.'
        return
    fi
    if [[ ! -f $file || ! -r $file ]]; then
        set_status 'Arquivo não encontrado.'
        return
    fi
    prompt_line "Importar \"$file\" ($format) para $id? Digite \"sim\": "
    if [[ $REPLY != sim ]]; then
        set_status 'Importação cancelada.'
        return
    fi
    run_external extension import "$format" "$id" "$file"
    rc=$?
    ext_reload
    if (( rc == 0 )); then set_status "Importação concluída em $id."; else set_status "npass import falhou (código $rc)."; fi
}

# Enter on the Extensions screen.
ext_activate() {
    local name=${EXT_NAMES[EXT_CURSOR]-} id why
    (( ${#EXT_NAMES[@]} )) || return 0
    if [[ ${EXT_STATE[EXT_CURSOR]} == refused ]]; then
        why=${EXT_WHY[EXT_CURSOR]}
        set_status "$name foi recusada pelo npass: ${EXT_WHY_TEXT[$why]:-$why}."
        return
    fi
    id=$(ext_target_id)
    case $name in
        audit | import)
            if [[ -z $id ]]; then set_status 'Nenhuma identidade selecionada.'; return; fi
            "ext_$name" "$id" ;;
        clip-x11)
            if [[ -z $id ]]; then set_status 'Nenhuma identidade selecionada.'; return; fi
            ext_clip_x11 "$id" ;;
        *) set_status "${EXT_USE[$name]:-Sem ação na TUI para $name.}" ;;
    esac
}
