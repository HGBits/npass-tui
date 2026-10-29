# Backend contract: everything that parses npass CLI output lives here.

# Minimum supported npass-store: MAJOR.MINOR. Same major required.
NPASS_MIN_MAJOR=2
NPASS_MIN_MINOR=8

# `npass help` prints "npass X.Y - ..." on its first line.
check_npass_version() {
    local first ver major minor
    [[ ${NPASS_TUI_SKIP_VERSION_CHECK:-0} == 1 ]] && return 0
    first=$("$NPASS_BIN" help 2>/dev/null | head -n 1)
    if [[ $first =~ ^npass[[:space:]]+([0-9]+)\.([0-9]+) ]]; then
        major=${BASH_REMATCH[1]}
        minor=${BASH_REMATCH[2]}
    else
        printf '%s: não foi possível determinar a versão do npass (esperado %d.%d+).\n' \
            "$APP_NAME" "$NPASS_MIN_MAJOR" "$NPASS_MIN_MINOR" >&2
        printf '%s: defina NPASS_TUI_SKIP_VERSION_CHECK=1 para ignorar.\n' "$APP_NAME" >&2
        return 1
    fi
    if (( major != NPASS_MIN_MAJOR || minor < NPASS_MIN_MINOR )); then
        printf '%s: npass %s.%s incompatível; requer %d.%d+ (mesma major).\n' \
            "$APP_NAME" "$major" "$minor" "$NPASS_MIN_MAJOR" "$NPASS_MIN_MINOR" >&2
        return 1
    fi
}

load_identities() {
    local output line ident rc
    if output=$("$NPASS_BIN" identities 2>&1); then
        :
    else
        rc=$?
        set_status "Erro ao listar identidades (código $rc)."
        return 1
    fi
    IDENTITIES=()
    while IFS= read -r line; do
        [[ -z ${line//[[:space:]]/} ]] && continue
        # npass identities emits summaries as "NAME - N passwords". Ignore
        # other successful output (for example, its localized empty-store
        # message) instead of treating it as an identity name.
        if [[ $line =~ ^(.*)[[:space:]]-[[:space:]]+[0-9]+[[:space:]]+(senha|senhas|password|passwords)$ ]]; then
            ident=${BASH_REMATCH[1]}
        else
            continue
        fi
        ident=${ident#"${ident%%[![:space:]]*}"}
        ident=${ident%"${ident##*[![:space:]]}"}
        [[ -n $ident ]] && IDENTITIES+=("$ident")
    done <<< "$output"
    if (( ${#IDENTITIES[@]} == 0 )); then
        set_status 'Nenhuma identidade encontrada.'
        return 1
    fi
}

load_paths() {
    local output line rc
    # Never leave paths from the previous identity selectable after an error.
    PATHS=()
    VISIBLE=()
    CURSOR=0
    OFFSET=0
    if output=$("$NPASS_BIN" ls --flat "$CURRENT_ID" 2>&1); then
        :
    else
        rc=$?
        set_status "Erro ao listar entradas (código $rc)."
        return 1
    fi
    while IFS= read -r line; do [[ -n $line ]] && PATHS+=("$line"); done <<< "$output"
    rebuild_visible
}

rebuild_visible() {
    local path
    VISIBLE=()
    for path in "${PATHS[@]}"; do
        [[ -z $QUERY || ${path,,} == *"${QUERY,,}"* ]] && VISIBLE+=("$path")
    done
    CURSOR=0
    OFFSET=0
}
