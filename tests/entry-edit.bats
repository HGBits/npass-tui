#!/usr/bin/env bats
load test_helper

@test "edita a entrada selecionada" {
  run run_tui edit
  [ "$status" -eq 0 ]
  assert_log_has 'edit personal example/login'
}
