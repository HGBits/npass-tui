#!/usr/bin/env bats
load test_helper

@test "identidades: rodapé só com atalhos da tela, sem status e sem duplicação" {
  run_tui_case footer-identities
  [ "$status" -eq 0 ]
}

@test "entradas: rodapé contextual completo, sem duplicação" {
  run_tui_case footer-entries
  [ "$status" -eq 0 ]
}

@test "preview: rodapé mostra só revelar, rolagem, cópia e voltar" {
  run_tui_case footer-preview
  [ "$status" -eq 0 ]
}

@test "menu de cópia: rodapé próprio e o menu sai da tela ao cancelar" {
  run_tui_case copy-menu-layout
  [ "$status" -eq 0 ]
}

@test "terminal estreito: atalhos de baixa prioridade caem e nada passa da largura" {
  PTY_COLS=40 run_tui_case footer-narrow
  [ "$status" -eq 0 ]
}

@test "status novo apaga os restos do status antigo" {
  run_tui_case status-replace
  [ "$status" -eq 0 ]
}

@test "status é transitório: some na tecla seguinte" {
  run_tui_case status-transient
  [ "$status" -eq 0 ]
}
