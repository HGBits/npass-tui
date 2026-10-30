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

@test "preview: rodapé mostra só rolagem, cópia, OTP e voltar" {
  run_tui_case footer-preview
  [ "$status" -eq 0 ]
}

@test "OTP: rodapé próprio e o código sai da tela ao voltar" {
  run_tui_case footer-otp
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
