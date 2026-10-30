#!/usr/bin/env bats
load test_helper

@test "preview abre oculto: nenhuma linha do conteúdo é desenhada até V" {
  MOCK_SHOW_CONTROL=1 MOCK_MANY=1 run_tui_case preview-protected
  [ "$status" -eq 0 ]
  # um único show por abertura; revelar/ocultar não decifra de novo
  [ "$(grep -Ec '^show ' "$LOG")" -eq 2 ]
}

@test "rolagem do preview para no fim, é independente da lista e zera ao ocultar" {
  MOCK_SHOW_LONG=1 run_tui_case preview-scroll
  [ "$status" -eq 0 ]
}

@test "OTP aberto de dentro do preview volta ao preview intacto" {
  MOCK_SHOW_CONTROL=1 run_tui_case preview-otp-return
  [ "$status" -eq 0 ]
}

@test "voltar do preview e editar preservam a seleção da lista" {
  run_tui_case preview-keeps-selection
  [ "$status" -eq 0 ]
}

@test "filtro: aplica, não casa nada, remove com valor vazio e zera ao reabrir" {
  run_tui_case filter
  [ "$status" -eq 0 ]
}
