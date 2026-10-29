# Backend contract: everything that parses npass CLI output lives here.

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
