#!/usr/bin/env bats
load test_helper

@test "X lista as extensões reportadas por npass extension list, nas identidades e nas entradas" {
  run_tui_case extensions
  [ "$status" -eq 0 ]
  assert_log_has 'extension list'
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
