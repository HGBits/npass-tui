#!/usr/bin/env bats
load test_helper

@test "X lista as extensões do npass com descrição, nas identidades e nas entradas" {
  run_tui_case extensions
  [ "$status" -eq 0 ]
  assert_log_has 'extension list'
}

@test "extensões sem ação na TUI só explicam o que fazer e não executam nada" {
  run_tui_case ext-no-action
  [ "$status" -eq 0 ]
  run grep -Eq '^extension (audit|import|clip-x11|passkey|wclip)' "$LOG"
  [ "$status" -ne 0 ]
}

@test "linha desconhecida do npass é mostrada, mas não tem ação" {
  MOCK_EXT_ODD=1 run_tui_case extensions-odd
  [ "$status" -eq 0 ]
}

@test "falha da CLI vira mensagem genérica, sem vazar a saída" {
  MOCK_EXT_FAIL=1 run_tui_case extensions-fail
  [ "$status" -eq 0 ]
}

@test "sem extensões instaladas mostra estado vazio" {
  MOCK_EXT_EMPTY=1 run_tui_case extensions-empty
  [ "$status" -eq 0 ]
}

@test "sequências de controle na saída das extensões não chegam ao terminal" {
  MOCK_EXT_CONTROL=1 run_tui_case extensions-control
  [ "$status" -eq 0 ]
}

@test "audit online: pergunta antes e chama npass audit ID" {
  MOCK_AUDIT_ANSWER=s run_tui_case ext-audit
  [ "$status" -eq 0 ]
  assert_log_has 'extension audit personal'
}

@test "audit offline: npass audit ID --offline" {
  MOCK_AUDIT_ANSWER=o run_tui_case ext-audit
  [ "$status" -eq 0 ]
  assert_log_has 'extension audit personal --offline'
}

@test "audit cancelado não executa nada (nada vai para a rede)" {
  MOCK_AUDIT_ANSWER= run_tui_case ext-audit
  [ "$status" -eq 0 ]
  run grep -Eq '^extension audit' "$LOG"
  [ "$status" -ne 0 ]
}

@test "falha do audit mostra o código e mantém a TUI de pé" {
  MOCK_ACTION_EXIT=3 run_tui_case ext-audit-fail
  [ "$status" -eq 0 ]
}

@test "audit usa a identidade selecionada quando aberto pela lista de identidades" {
  MOCK_TWO_IDS=1 run_tui_case ext-audit-identity
  [ "$status" -eq 0 ]
  assert_log_has 'extension audit work --offline'
}

@test "import: formato, arquivo e confirmação; a lista é recarregada depois" {
  run_tui_case ext-import
  [ "$status" -eq 0 ]
  run grep -Eq '^extension import bitwarden personal /' "$LOG"
  [ "$status" -eq 0 ]
  [ "$(grep -Ec '^ls ' "$LOG")" -ge 2 ]
}

@test "import recusa formato/arquivo inválidos e sem confirmação não executa" {
  run_tui_case ext-import-invalid
  [ "$status" -eq 0 ]
  run grep -Eq '^extension import' "$LOG"
  [ "$status" -ne 0 ]
}

@test "extensão recusada pelo npass aparece com o motivo e não é executada" {
  MOCK_EXT_REFUSED=1 run_tui_case extensions-refused
  [ "$status" -eq 0 ]
  run grep -Eq '^extension (audit|import|clip-x11)' "$LOG"
  [ "$status" -ne 0 ]
}

@test "sem diretório de extensões o aviso do npass aparece no lugar da lista" {
  MOCK_EXT_NODIR=1 run_tui_case extensions-nodir
  [ "$status" -eq 0 ]
}

@test "ext_load entende 'nome: ok', 'nome: recusada (motivo)' e guarda o resto como aviso" {
  run bash -c "source '$ROOT/lib/00-core.bash' 2>/dev/null; source '$ROOT/lib/05-extensions.bash'
    NPASS_BIN='$MOCK_NPASS' NPASS_LOG=/dev/null MOCK_EXT_REFUSED=1 ext_load
    printf '%s|%s|%s\\n' \"\${EXT_NAMES[*]}\" \"\${EXT_STATE[*]}\" \"\${EXT_WHY[*]}\"
    NPASS_BIN='$MOCK_NPASS' NPASS_LOG=/dev/null MOCK_EXT_NODIR=1 ext_load
    printf '%s|%s\\n' \"\${#EXT_NAMES[@]}\" \"\${#EXT_INFO[@]}\""
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "audit import clip-x11|refused ok refused|assinatura_invalida  permissao" ]
  [ "${lines[1]}" = "0|1" ]
}

@test "clip-x11 na tela de extensões copia a senha sem exibir o conteúdo" {
  MOCK_SESSION=x11 MOCK_DISPLAY=:99 MOCK_CLIP_ANSWER= run_tui_case ext-clip-x11
  [ "$status" -eq 0 ]
  assert_log_has 'extension clip-x11 personal example/login'
}

@test "clip-x11 aceita campo específico e documento inteiro" {
  MOCK_SESSION=x11 MOCK_DISPLAY=:99 MOCK_CLIP_ANSWER=login run_tui_case ext-clip-x11
  [ "$status" -eq 0 ]
  assert_log_has 'extension clip-x11 login personal example/login'
  MOCK_SESSION=x11 MOCK_DISPLAY=:99 MOCK_CLIP_ANSWER=all run_tui_case ext-clip-x11
  [ "$status" -eq 0 ]
  assert_log_has 'extension clip-x11 all personal example/login'
}

@test "clip-x11 não executa fora de uma sessão X11" {
  MOCK_SESSION=wayland run_tui_case ext-clip-x11-no-session
  [ "$status" -eq 0 ]
  run grep -Eq '^extension clip-x11' "$LOG"
  [ "$status" -ne 0 ]
}

@test "clip-x11 recusa nome de campo inválido sem chamar a extensão" {
  MOCK_SESSION=x11 MOCK_DISPLAY=:99 MOCK_CLIP_ANSWER=--help run_tui_case ext-clip-x11
  [ "$status" -eq 0 ]
  run grep -Eq '^extension clip-x11' "$LOG"
  [ "$status" -ne 0 ]
}

@test "clip-x11 recusada pelo npass nunca é executada pela ação explícita" {
  MOCK_SESSION=x11 MOCK_DISPLAY=:99 MOCK_EXT_REFUSED=1 run_tui_case ext-clip-x11-refused
  [ "$status" -eq 0 ]
  run grep -Eq '^extension clip-x11' "$LOG"
  [ "$status" -ne 0 ]
}

@test "falha de clip-x11 não exibe a saída arbitrária da extensão" {
  MOCK_SESSION=x11 MOCK_DISPLAY=:99 MOCK_CLIP_FAIL=1 run_tui_case ext-clip-x11
  [ "$status" -eq 0 ]
  run grep -Fq 'FAIL-SECRET-SENTINEL' "$PTY_OUT"
  [ "$status" -ne 0 ]
}

@test "clip-x11 não executa sem uma entrada selecionada" {
  MOCK_SESSION=x11 MOCK_DISPLAY=:99 run_tui_case ext-clip-x11-without-entry
  [ "$status" -eq 0 ]
  run grep -Eq '^extension clip-x11' "$LOG"
  [ "$status" -ne 0 ]
}

@test "TUI rejeita nomes de artefato com prefixo npass- duplicado" {
  MOCK_EXT_PREFIXED=1 run_tui_case extensions
  [ "$status" -eq 0 ]
  run bash -c "source '$ROOT/lib/00-core.bash' 2>/dev/null; source '$ROOT/lib/05-extensions.bash'; NPASS_BIN='$MOCK_NPASS' NPASS_LOG=/dev/null MOCK_EXT_PREFIXED=1 ext_load; printf '%s' "\${EXT_NAMES[*]}""
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
