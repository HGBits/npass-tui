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
  run grep -Eq '^(passkey|clip-x11|wclip|audit|import)' "$LOG"
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
  assert_log_has 'audit personal'
}

@test "audit offline: npass audit ID --offline" {
  MOCK_AUDIT_ANSWER=o run_tui_case ext-audit
  [ "$status" -eq 0 ]
  assert_log_has 'audit personal --offline'
}

@test "audit cancelado não executa nada (nada vai para a rede)" {
  MOCK_AUDIT_ANSWER= run_tui_case ext-audit
  [ "$status" -eq 0 ]
  run grep -Eq '^audit' "$LOG"
  [ "$status" -ne 0 ]
}

@test "falha do audit mostra o código e mantém a TUI de pé" {
  MOCK_ACTION_EXIT=3 run_tui_case ext-audit-fail
  [ "$status" -eq 0 ]
}

@test "audit usa a identidade selecionada quando aberto pela lista de identidades" {
  MOCK_TWO_IDS=1 run_tui_case ext-audit-identity
  [ "$status" -eq 0 ]
  assert_log_has 'audit work --offline'
}

@test "import: formato, arquivo e confirmação; a lista é recarregada depois" {
  run_tui_case ext-import
  [ "$status" -eq 0 ]
  run grep -Eq '^import bitwarden personal /' "$LOG"
  [ "$status" -eq 0 ]
  [ "$(grep -Ec '^ls ' "$LOG")" -ge 2 ]
}

@test "import recusa formato/arquivo inválidos e sem confirmação não executa" {
  run_tui_case ext-import-invalid
  [ "$status" -eq 0 ]
  run grep -Eq '^import' "$LOG"
  [ "$status" -ne 0 ]
}

@test "formatos variados de extension list (bullets, cores, caminhos, tabela) acham audit e import" {
  for fmt in bullets ansi paths table; do
    MOCK_EXT_FORMAT=$fmt run_tui_case extensions-format
    if (( status != 0 )); then echo "formato: $fmt" >&2; fi
    [ "$status" -eq 0 ]
  done
}

@test "nome da extensão sai de linhas como npass-audit, audit.bash, caminhos e bullets" {
  run bash -c "source '$ROOT/lib/00-core.bash' 2>/dev/null; source '$ROOT/lib/05-extensions.bash'
    for l in 'npass-audit  0.1.0' 'audit - Audita' '* audit' '[ok] npass-audit' '/usr/lib/npass/extensions/npass-audit' 'npass-import.bash' 'clip-x11 (xclip)' 'npass-clip-x11.bash' '  ● passkey'; do
      ext_name_of \"\$l\"; printf '%s\\n' \"\$EXT_FOUND\"
    done"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'audit\naudit\naudit\naudit\naudit\nimport\nclip-x11\nclip-x11\npasskey')" ]
}
