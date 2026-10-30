# Keyboard input: translates key presses into logical REPLY tokens.

read_key() {
    local key seq rc
    # Poll with a timeout so pending signal traps run even while the user is idle.
    while :; do
        # SIGWINCH only sets WINCH; the main loop re-reads the size.
        if (( WINCH )); then WINCH=0; REPLY=resize; return; fi
        if IFS= read -r -s -n 1 -t 0.2 key; then
            break
        else
            rc=$?
        fi
        # Bash read returns >128 on timeout; EOF or a closed terminal means quit.
        if (( rc > 128 )); then
            continue
        fi
        REPLY=quit
        return
    done
    if [[ $key == "$ESC" ]]; then
        IFS= read -r -s -n 1 -t 0.03 seq || seq=''
        if [[ $seq == '[' || $seq == 'O' ]]; then
            IFS= read -r -s -n 1 -t 0.03 key || key=''
            case $key in A) REPLY=up ;; B) REPLY=down ;; C) REPLY=right ;; D) REPLY=left ;; *) REPLY=unknown ;; esac
        else
            REPLY=back
        fi
        return
    fi
    case $key in
        $'\n'|$'\r'|'') REPLY=enter ;;
        q|Q) REPLY=quit ;;
        j) REPLY=down ;;
        k) REPLY=up ;;
        a|A) REPLY=add ;;
        e|E) REPLY=edit ;;
        d|D) REPLY=delete ;;
        c|C) REPLY=clip ;;
        o|O) REPLY=otp ;;
        v|V) REPLY=reveal ;;
        /) REPLY=search ;;
        *) REPLY=unknown ;;
    esac
}
