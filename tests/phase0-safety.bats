#!/usr/bin/env bats
load test_helper

@test "saída da CLI com sequências de controle não é executada no terminal" {
  MOCK_SHOW_CONTROL=1 run_tui_case control-output
  [ "$status" -eq 0 ]
  assert_log_has 'show --raw personal example/login'
}

@test "SIGTERM restaura os atributos do terminal e mostra o cursor" {
  run_tui_case signal-term
  [ "$status" -eq 0 ]
}

@test "OTP fica no preview explícito, não no status nem no log de argumentos" {
  run_tui_case otp-secret
  [ "$status" -eq 0 ]
  assert_log_has 'otp personal example/login'
  run grep -Fq 'OTP-SENTINEL-123456' "$LOG"
  [ "$status" -ne 0 ]
}

@test "falha ao listar identidades não exibe texto arbitrário da CLI" {
  MOCK_IDENTITIES_FAIL=1 run_tui_case identities-fail
  [ "$status" -eq 0 ]
}

@test "falha ao listar entradas não exibe texto arbitrário da CLI" {
  MOCK_LS_FAIL=1 run_tui_case ls-fail
  [ "$status" -eq 0 ]
}

@test "falha no preview não expõe saída da CLI no status" {
  MOCK_SHOW_FAIL=1 run_tui_case show-fail-secret
  [ "$status" -eq 0 ]
  assert_log_has 'show --raw personal example/login'
}

@test "falha no clipboard não expõe saída da CLI no status" {
  MOCK_CLIP_FAIL=1 run_tui_case clip-fail-secret
  [ "$status" -eq 0 ]
  assert_log_has 'clip personal example/login'
}

@test "falha no OTP não expõe o código nem a saída da CLI no status" {
  MOCK_OTP_FAIL=1 run_tui_case otp-fail-secret
  [ "$status" -eq 0 ]
  assert_log_has 'otp personal example/login'
}

@test "SIGINT restaura o terminal e mostra o cursor" {
  run_tui_case signal-int
  [ "$status" -eq 0 ]
}

@test "SIGHUP restaura o terminal e mostra o cursor" {
  run_tui_case signal-hup
  [ "$status" -eq 0 ]
}

@test "saída normal restaura os atributos do terminal e mostra o cursor" {
  run_tui_case exit-cleanup
  [ "$status" -eq 0 ]
}
