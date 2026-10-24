#!/usr/bin/env bats
load test_helper

@test "carrega identidades e caminhos ao entrar" {
  run run_tui create
  [ "$status" -eq 0 ]
  assert_log_has 'identities'
  assert_log_has 'tree --flat personal'
}
