#!/usr/bin/env bats
load test_helper

@test "carrega identidades e caminhos ao entrar e cria sem force" {
  run run_tui create
  [ "$status" -eq 0 ]
  assert_log_has 'identities'
  assert_log_has 'tree --flat personal'
  assert_log_has 'insert personal new/site'
  ! grep -Eq '^insert .* (-f|--force)( |$)' "$LOG"
}

@test "caminho vazio cancela a criação" {
  run run_tui cancel
  [ "$status" -eq 0 ]
  ! grep -Eq '^insert ' "$LOG"
}
