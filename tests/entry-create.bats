#!/usr/bin/env bats
load test_helper

@test "carrega identidades e caminhos ao entrar e cria sem force" {
  run_tui_case create
  [ "$status" -eq 0 ]
  assert_log_has 'identities'
  assert_log_has 'ls --flat personal'
  assert_log_has 'insert personal new/site'
  run grep -Eq '^insert .* (-f|--force)( |$)' "$LOG"
  [ "$status" -ne 0 ]
}

@test "caminho vazio cancela a criação" {
  run_tui_case cancel
  [ "$status" -eq 0 ]
  run grep -Eq '^insert ' "$LOG"
  [ "$status" -ne 0 ]
}
