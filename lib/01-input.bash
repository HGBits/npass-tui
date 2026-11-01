# Keyboard input: translates key presses into logical REPLY tokens.

read_key() {
    local key seq rc
    # A plain blocking read: bash drops a key that arrives just as `read -t`
    # expires, so there is no polling timeout here. SIGINT/TERM/HUP exit through
    # their traps; SIGWINCH repaints from its trap (see on_winch).
    while :; do
        if (( WINCH )); then WINCH=0; REPLY=resize; return; fi
        IN_READ=1
        if IFS= read -r -s -n 1 key; then
            IN_READ=0
            break
        else
            rc=$?
            IN_READ=0
        fi
        (( rc > 128 )) && continue
        # EOF or a closed terminal means quit.
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
        x|X) REPLY=extensions ;;
        v|V) REPLY=reveal ;;
        /) REPLY=search ;;
        *) REPLY=unknown ;;
    esac
}
