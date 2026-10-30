# Rendering. The screen is described as regions ("cells": a row, a column, a
# width and a string). paint() remembers what each region already shows and
# only sends it to the terminal when it changed, so a key press that moves the
# selection rewrites two rows instead of the whole window.
#
# Every string reaching the terminal goes through paint()/sanitize_text.

OUT=''          # frame buffer: render() builds one string and writes it at once
declare -A CELL=()  # region key "row:col" -> what is currently drawn there
R_FULL=1        # next render clears the screen and repaints everything
CUP_STD=0       # 1 when the terminal's cup is plain CSI (no tput fork per move)
TOO_SMALL=0

MIN_ROWS=10
MIN_COLS=40
# Split view needs room for both panes; below that the layout is compact and
# shows one pane at a time.
EX_MIN=24
CT_MIN=24

# Geometry, recomputed by compute_layout(). Explorer on the left (~40%),
# Context on the right, a one-cell separator between them.
HDR_ROW=0 RULE_TOP=1 TITLE_ROW=2 BODY_TOP=3 BODY_H=0 RULE_BOT=0 STATUS_ROW=0 KEYS_ROW=0
SPLIT=0 EX_COL=0 EX_W=0 CT_COL=0 CT_W=0
RULE_TOP_TXT='' RULE_BOT_TXT=''
CTX=() CTX_A=()   # lines (and their attributes) of the Context pane

render_init() {
    [[ $(tput cup 0 0 2>/dev/null) == $'\033[1;1H' && $(tput cup 11 79 2>/dev/null) == $'\033[12;80H' ]] && CUP_STD=1
    term_size
    R_FULL=1
}

# cup ROW COL (0-based) appended to the frame buffer.
cup() {
    if (( CUP_STD )); then
        OUT+=$'\033['$(($1 + 1))';'$(($2 + 1))'H'
    else
        OUT+=$(tput cup "$1" "$2" 2>/dev/null)
    fi
}

flush() {
    [[ -n $OUT ]] || return 0
    printf '%s' "$OUT"
    OUT=''
}

# paint ROW COL WIDTH TEXT [ATTR]
# Draws TEXT padded (or cut, with an ellipsis) to exactly WIDTH cells, but only
# when the region differs from what is already on screen. Padding erases any
# leftover of a longer previous text.
paint() {
    local row=$1 col=$2 width=$3 text=$4 attr=${5:-} key sig len
    (( width > 0 )) || return 0
    key="$row:$col"
    sig="$width|$attr|$text"
    [[ ${CELL[$key]-} == "$sig" ]] && return 0
    if [[ -z ${CELL[$key]+x} && -z $text && -z $attr ]]; then
        # Never drawn and blank: the cleared screen already shows exactly this.
        CELL[$key]=$sig
        return 0
    fi
    CELL[$key]=$sig
    [[ $text == *[[:cntrl:]]* ]] && text=$(sanitize_text "$text")
    len=${#text}
    if (( len > width )); then
        text=${text:0:width-${#G_ELL}}$G_ELL
        len=$width
    fi
    cup "$row" "$col"
    OUT+=$attr$text${SPACES:0:width-len}
    [[ -n $attr ]] && OUT+=$RESET
}

compute_layout() {
    TOO_SMALL=0
    (( ROWS < MIN_ROWS || COLS < MIN_COLS )) && TOO_SMALL=1
    BODY_H=$((ROWS - 6))
    (( BODY_H >= 1 )) || BODY_H=1
    RULE_BOT=$((ROWS - 3))
    STATUS_ROW=$((ROWS - 2))
    KEYS_ROW=$((ROWS - 1))
    EX_COL=0
    if (( COLS >= EX_MIN + 1 + CT_MIN )); then
        SPLIT=1
        EX_W=$((COLS * 40 / 100))
        (( EX_W >= EX_MIN )) || EX_W=$EX_MIN
        (( EX_W <= COLS - 1 - CT_MIN )) || EX_W=$((COLS - 1 - CT_MIN))
        CT_COL=$((EX_W + 1))
        CT_W=$((COLS - CT_COL))
        RULE_TOP_TXT=${HRULE:0:EX_W}$G_TD${HRULE:CT_COL}
        RULE_BOT_TXT=${HRULE:0:EX_W}$G_TU${HRULE:CT_COL}
    else
        SPLIT=0
        EX_W=$COLS CT_COL=0 CT_W=$COLS
        RULE_TOP_TXT=$HRULE RULE_BOT_TXT=$HRULE
    fi
}

# Keep CURSOR inside the list and the list window (OFFSET) around it.
clamp_view() {
    local n=$1
    (( CURSOR < n )) || CURSOR=$((n - 1))
    (( CURSOR >= 0 )) || CURSOR=0
    (( CURSOR >= OFFSET )) || OFFSET=$CURSOR
    (( CURSOR < OFFSET + BODY_H )) || OFFSET=$((CURSOR - BODY_H + 1))
    (( OFFSET + BODY_H <= n )) || OFFSET=$((n - BODY_H))
    (( OFFSET >= 0 )) || OFFSET=0
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
        identities) items=("1|$G_UPDN|Navegar" '1|Enter|Abrir' '1|Q|Sair') ;;
        entries) items=("1|$G_UPDN|Navegar" '1|Enter|Abrir' '2|/|Filtrar' '3|A|Criar' '3|E|Editar'
                        '3|D|Excluir' '2|C|Copiar' '2|O|OTP' '1|Esc|Voltar') ;;
        preview) items=("1|$G_UPDN|Rolar" '2|C|Copiar' '2|O|OTP' '1|Esc|Voltar') ;;
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

draw_header() {
    local where='COFRE / IDENTIDADES'
    case $SCREEN in
        entries) where="COFRE / $CURRENT_ID" ;;
        preview) where="COFRE / $CURRENT_ID / ${VISIBLE[CURSOR]-}" ;;
        otp) where="COFRE / $CURRENT_ID / OTP" ;;
    esac
    paint "$HDR_ROW" 0 "$COLS" " npass-tui  $where" "$BOLD$REV"
    paint "$RULE_TOP" 0 "$COLS" "$RULE_TOP_TXT"
}

draw_footer() {
    paint "$RULE_BOT" 0 "$COLS" "$RULE_BOT_TXT"
    paint "$STATUS_ROW" 0 "$COLS" "$STATUS" "$DIM"
    footer_keys
    paint "$KEYS_ROW" 0 "$COLS" "$FOOTER_TEXT"
}

# The Explorer lists identities, or the entries of the current identity once one
# is open. While a preview/OTP is on the right, the Explorer keeps showing the
# list but the selection is only bold: the focus is on the right.
draw_explorer() {
    local title empty_msg='' i idx row n
    local src=IDENTITIES attr_sel=$REV
    case $SCREEN in
        identities)
            title='IDENTIDADES'
            empty_msg='Nenhuma identidade. Crie uma com: npass init' ;;
        *)
            src=VISIBLE title='ENTRADAS'
            if [[ -n $QUERY ]]; then
                empty_msg='Nenhuma entrada corresponde ao filtro. Use / com valor vazio para remover.'
            else
                empty_msg='Identidade sem entradas. Pressione a para criar a primeira.'
            fi ;;
    esac
    [[ $SCREEN == preview || $SCREEN == otp ]] && attr_sel=$BOLD
    local -n items=$src
    n=${#items[@]}
    clamp_view "$n"
    (( n > 0 )) && title+="  $((CURSOR + 1))/$n"
    [[ $src == VISIBLE && -n $QUERY ]] && title+="  filtro: $QUERY"
    paint "$TITLE_ROW" "$EX_COL" "$EX_W" " $title" "$BOLD"
    for ((i = 0; i < BODY_H; i++)); do
        idx=$((OFFSET + i))
        row=$((BODY_TOP + i))
        if (( idx < n )); then
            if (( idx == CURSOR )); then
                paint "$row" "$EX_COL" "$EX_W" "> ${items[idx]}" "$attr_sel"
            else
                paint "$row" "$EX_COL" "$EX_W" "  ${items[idx]}"
            fi
        elif (( n == 0 && i == 1 )); then
            paint "$row" "$EX_COL" "$EX_W" "  $empty_msg"
        else
            paint "$row" "$EX_COL" "$EX_W" ''
        fi
    done
}

draw_separator() {
    local r
    (( SPLIT )) || return 0
    for ((r = TITLE_ROW; r < RULE_BOT; r++)); do paint "$r" $((CT_COL - 1)) 1 "$G_V"; done
}

ctx_add() { CTX+=("$1"); CTX_A+=("${2:-}"); }

# ctx_field LABEL VALUE: "Label:      value" with the value aligned.
ctx_field() {
    local label=$1
    local pad=$((13 - ${#label}))
    (( pad >= 1 )) || pad=1
    ctx_add "$label${SPACES:0:pad}$2"
}

ctx_identity() {
    local name=${IDENTITIES[CURSOR]-}
    if [[ -z $name ]]; then
        ctx_add 'Nenhuma identidade selecionada.'
        return
    fi
    ctx_add "$name" "$BOLD"
    ctx_add ''
    # The count is what `npass identities` reports; it may include attachments.
    ctx_field 'Contagem:' "${IDENT_INFO[CURSOR]-?} (segundo o npass)"
    ctx_add ''
    ctx_add 'Enter abre a lista de entradas.'
}

ctx_entry() {
    local path=${VISIBLE[CURSOR]-} folder name
    if [[ -z $path ]]; then
        ctx_add 'Nenhuma entrada selecionada.'
        return
    fi
    name=${path##*/}
    folder='(raiz)'
    [[ $path == */* ]] && folder=${path%/*}
    ctx_add "$name" "$BOLD"
    ctx_add ''
    ctx_field 'Pasta:' "$folder"
    ctx_field 'Identidade:' "$CURRENT_ID"
    ctx_field 'Posição:' "$((CURSOR + 1)) de ${#VISIBLE[@]}"
    ctx_add ''
    ctx_field 'Proteção:' 'conteúdo oculto'
    ctx_add "             Só é lido com Enter."
    ctx_add ''
    ctx_add 'Enter abrir  C copiar  O OTP'
    ctx_add 'E editar  D excluir'
}

# draw_context TITLE: paints CTX/CTX_A (or the preview lines) into the right pane.
draw_context() {
    local title=$1 i row
    paint "$TITLE_ROW" "$CT_COL" "$CT_W" " $title" "$BOLD"
    for ((i = 0; i < BODY_H; i++)); do
        row=$((BODY_TOP + i))
        if (( i < ${#CTX[@]} )); then
            paint "$row" "$CT_COL" "$CT_W" " ${CTX[i]}" "${CTX_A[i]}"
        else
            paint "$row" "$CT_COL" "$CT_W" ''
        fi
    done
}

# Scrollable text (preview and OTP) in the right pane.
draw_text() {
    local title=$1 i row
    local -n lines=$2
    local off=$3
    paint "$TITLE_ROW" "$CT_COL" "$CT_W" " $title" "$BOLD"
    for ((i = 0; i < BODY_H; i++)); do
        row=$((BODY_TOP + i))
        if (( off + i < ${#lines[@]} )); then
            paint "$row" "$CT_COL" "$CT_W" " ${lines[off+i]}"
        else
            paint "$row" "$CT_COL" "$CT_W" ''
        fi
    done
}

draw_too_small() {
    local i
    paint 0 0 "$COLS" "Terminal pequeno demais: ${COLS}x${ROWS}" "$BOLD"
    paint 1 0 "$COLS" "Mínimo: ${MIN_COLS}x${MIN_ROWS}. Redimensione ou Q para sair."
    for ((i = 2; i < ROWS; i++)); do paint "$i" 0 "$COLS" ''; done
}

render() {
    if (( R_FULL )); then
        OUT+=$CLEAR
        CELL=()
        R_FULL=0
    fi
    compute_layout
    if (( TOO_SMALL )); then
        draw_too_small
        flush
        return
    fi
    draw_header
    case $SCREEN in
        identities | entries)
            draw_explorer
            if (( SPLIT )); then
                CTX=() CTX_A=()
                if [[ $SCREEN == identities ]]; then ctx_identity; else ctx_entry; fi
                draw_context 'CONTEXTO'
            fi ;;
        preview | otp)
            (( SPLIT )) && draw_explorer
            if [[ $SCREEN == preview ]]; then
                draw_text 'CONTEÚDO' PREVIEW_LINES "$PREVIEW_OFFSET"
            else
                draw_text 'CÓDIGO OTP' OTP_LINES 0
            fi ;;
    esac
    draw_separator
    draw_footer
    flush
}

# Show STATUS on the next frame (it is transient: any key clears it).
show_message() {
    set_status "$1"
}
