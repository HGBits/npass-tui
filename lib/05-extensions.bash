# Extensions: optional commands installed next to npass and called as
# `npass NAME ...`. `npass extension list` is the source of truth for what is
# installed. Two things use them:
#   - the copy menu picks the clipboard backend (clip, or clip-x11 on X11);
#   - the Extensions screen (X) runs the ones that have a TUI action.

EXT_NAMES=()      # short name per listed extension ("" when no word looks like one)
EXT_FOUND=''
EXT_RAW=()        # the line as `npass extension list` printed it
EXT_CURSOR=0
EXT_LOADED=0
EXT_RC=0
CLIP_CMD=clip     # command behind "copy": clip, clip-x11 or wclip
CLIP_NOTE=''      # why, when it is not the default

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
    [passkey]='Sem ação na TUI. Use na CLI: npass passkey.'
    [clip-x11]='Usada pelo menu Copiar em sessões X11, sem ação aqui.'
    [wclip]='Usada pelo menu Copiar com NPASS_TUI_CLIP=wclip, sem ação aqui.'
)

# Short name of the extension a `npass extension list` line talks about, in
# EXT_FOUND. The core's format is not fixed here, so be lenient: the line is
# split into words (anything but letters, digits and "-" separates), and the
# first word that is a known extension wins ("npass-audit", "audit.bash",
# "/usr/lib/npass/extensions/npass-audit", "* audit - ..." and "[ok] audit"
# all give "audit"). Without a known one, the first plain word is used.
ext_name_of() {
    local words=${1//[^A-Za-z0-9-]/ } word first=''
    EXT_FOUND=''
    set -f
    for word in $words; do
        word=${word,,}
        word=${word#npass-}
        [[ $word == bash ]] && continue
        if [[ -n ${EXT_DESC[$word]+x} ]]; then
            EXT_FOUND=$word
            set +f
            return 0
        fi
        [[ -z $first && $word =~ ^[a-z][a-z0-9-]{0,31}$ ]] && first=$word
    done
    set +f
    EXT_FOUND=$first
}

# Fills EXT_NAMES/EXT_RAW from `npass extension list`. Returns 1, with the exit
# code in EXT_RC, when the command is not available.
ext_load() {
    local output line
    output=$("$NPASS_BIN" extension list 2>&1) || { EXT_RC=$?; return 1; }
    output=$(sanitize_text "$output")
    EXT_NAMES=() EXT_RAW=()
    while IFS= read -r line; do
        line=${line#"${line%%[![:space:]]*}"}
        [[ -n $line ]] || continue
        ext_name_of "$line"
        EXT_NAMES+=("$EXT_FOUND")
        EXT_RAW+=("$line")
    done <<< "$output"
    EXT_LOADED=1
}

ext_installed() {
    local n
    for n in "${EXT_NAMES[@]}"; do [[ $n == "$1" ]] && return 0; done
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
        s | S) run_external audit "$id"; rc=$? ;;
        o | O) run_external audit "$id" --offline; rc=$? ;;
        *) set_status 'Auditoria cancelada.'; return ;;
    esac
    if (( rc == 0 )); then set_status "Auditoria de $id concluída."; else set_status "npass audit falhou (código $rc)."; fi
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
    run_external import "$format" "$id" "$file"
    rc=$?
    ext_reload
    if (( rc == 0 )); then set_status "Importação concluída em $id."; else set_status "npass import falhou (código $rc)."; fi
}

# Enter on the Extensions screen.
ext_activate() {
    local name=${EXT_NAMES[EXT_CURSOR]-} id
    (( ${#EXT_RAW[@]} )) || return 0
    id=$(ext_target_id)
    case $name in
        audit | import)
            if [[ -z $id ]]; then set_status 'Nenhuma identidade selecionada.'; return; fi
            "ext_$name" "$id" ;;
        '') set_status 'Sem ação na TUI para esta extensão.' ;;
        *) set_status "${EXT_USE[$name]:-Sem ação na TUI para $name.}" ;;
    esac
}
