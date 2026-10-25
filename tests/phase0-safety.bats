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
