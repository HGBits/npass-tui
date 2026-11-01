#!/usr/bin/env bats
load test_helper

@test "C abre o menu; Senha é o padrão e chama npass clip ID CAMINHO" {
  run_tui_case copy-password
  [ "$status" -eq 0 ]
  assert_log_has 'clip personal example/login'
}

@test "campo escolhido vai antes do ID: npass clip CAMPO ID CAMINHO" {
  run_tui_case copy-field
  [ "$status" -eq 0 ]
  assert_log_has 'clip login personal example/login'
  assert_log_has 'clip pin personal example/login'
}

@test "OTP é copiado por npass otp clip; o código nunca é pedido nem exibido" {
  run_tui_case copy-otp
  [ "$status" -eq 0 ]
  assert_log_has 'otp clip personal example/login'
  run grep -Eq '^otp personal' "$LOG"
  [ "$status" -ne 0 ]
}

@test "documento inteiro usa o campo all" {
  run_tui_case copy-all
  [ "$status" -eq 0 ]
  assert_log_has 'clip all personal example/login'
}

@test "outro campo: aceita nome válido, recusa nome com traço inicial e cancela se vazio" {
  run_tui_case copy-other
  [ "$status" -eq 0 ]
  assert_log_has 'clip api-key personal example/login'
  run grep -Fq -- '--help' "$LOG"
  [ "$status" -ne 0 ]
  [ "$(grep -Ec '^clip ' "$LOG")" -eq 1 ]
}

@test "a tecla O não faz mais nada e npass otp nunca é chamado" {
  run_tui_case copy-no-otp-key
  [ "$status" -eq 0 ]
  run grep -Eq '^otp' "$LOG"
  [ "$status" -ne 0 ]
}

@test "Esc cancela o menu sem executar nada" {
  run_tui_case copy-menu-layout
  [ "$status" -eq 0 ]
  run grep -Eq '^(clip|otp)' "$LOG"
  [ "$status" -ne 0 ]
}
