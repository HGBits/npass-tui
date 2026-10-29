# Entry point: environment checks, terminal setup and the main loop.
# Keep this file last (99-): build.sh concatenates lib/*.bash in order.
set -uo pipefail

APP_NAME=${APP_NAME:-npass-tui}
NPASS_BIN=${NPASS_BIN:-npass}

main_loop() {
    load_identities || true
    raw_mode
    while :; do
        render_current
        read_key
        case $SCREEN:$REPLY in
            identities:quit) break ;;
            identities:up) (( CURSOR > 0 )) && ((CURSOR--)) ;;
            identities:down) (( CURSOR + 1 < ${#IDENTITIES[@]} )) && ((CURSOR++)) ;;
            identities:enter)
                if (( ${#IDENTITIES[@]} > 0 )); then
                    CURRENT_ID=${IDENTITIES[CURSOR]}
                    SCREEN=entries; QUERY=''
                    if load_paths; then
                        set_status 'Enter abrir  c copiar senha  o OTP  / filtrar  Esc voltar'
                    fi
                fi ;;
            entries:quit|entries:back) SCREEN=identities; QUERY=''; set_status 'Escolha uma identidade.' ;;
            entries:up) (( CURSOR > 0 )) && ((CURSOR--)) ;;
            entries:down) (( CURSOR + 1 < ${#VISIBLE[@]} )) && ((CURSOR++)) ;;
            entries:search) search_prompt ;;
            entries:add)
                if prompt_path; then run_interactive_npass insert "$REPLY"; fi ;;
            entries:edit)
                if (( ${#VISIBLE[@]} > 0 )); then run_interactive_npass edit "${VISIBLE[CURSOR]}"; fi ;;
            entries:delete)
                if (( ${#VISIBLE[@]} > 0 )) && confirm_delete "${VISIBLE[CURSOR]}"; then
                    run_interactive_npass rm "$REPLY"
                fi ;;
            entries:enter) if (( ${#VISIBLE[@]} > 0 )); then open_preview "${VISIBLE[CURSOR]}"; fi ;;
            entries:clip) if (( ${#VISIBLE[@]} > 0 )); then run_action clip "${VISIBLE[CURSOR]}"; fi ;;
            entries:otp) if (( ${#VISIBLE[@]} > 0 )); then run_action otp "${VISIBLE[CURSOR]}"; fi ;;
            preview:quit|preview:back)
                SCREEN=entries
                PREVIEW_LINES=()
                PREVIEW_OFFSET=0 ;;
            preview:up) (( PREVIEW_OFFSET > 0 )) && ((PREVIEW_OFFSET--)) ;;
            preview:down) (( PREVIEW_OFFSET + 1 < ${#PREVIEW_LINES[@]} )) && ((PREVIEW_OFFSET++)) ;;
            preview:clip) run_action clip "${VISIBLE[CURSOR]}" ;;
            preview:otp) run_action otp "${VISIBLE[CURSOR]}" ;;
        esac
    done
}

main() {
    if ! command -v tput >/dev/null 2>&1; then
        printf '%s: dependência ausente: tput (ncurses/terminfo).\n' "$APP_NAME" >&2
        exit 1
    fi
    if ! command -v "$NPASS_BIN" >/dev/null 2>&1; then
        printf '%s: npass não encontrado; defina NPASS_BIN=/caminho/para/npass.\n' "$APP_NAME" >&2
        exit 1
    fi
    if [[ ! -t 0 || ! -t 1 ]]; then
        printf '%s: execute em um terminal interativo.\n' "$APP_NAME" >&2
        exit 1
    fi

    check_npass_version || exit 1

    TTY_STATE=$(stty -g)
    install_traps
    main_loop
}

main "$@"
