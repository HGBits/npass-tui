#!/usr/bin/env bats
load test_helper

@test "edita a entrada selecionada" {
  run_tui_case edit
  [ "$status" -eq 0 ]
  assert_log_has 'edit personal example/login'
}

@test "falha da CLI restaura o modo da TUI e entrega o terminal normal ao comando" {
  MOCK_ACTION_EXIT=17 run_tui_case edit-fail
  [ "$status" -eq 0 ]
  assert_log_has 'edit personal example/login'
}
