#!/usr/bin/env bats
load test_helper

@test "edita a entrada selecionada" {
  run_tui_case edit
  [ "$status" -eq 0 ]
  assert_log_has 'edit personal example/login'
}

@test "falha da CLI nao encerra a TUI nem fica presa no pseudo-terminal" {
  MOCK_ACTION_EXIT=17 run_tui_case edit-fail
  [ "$status" -eq 0 ]
  assert_log_has 'edit personal example/login'
}
