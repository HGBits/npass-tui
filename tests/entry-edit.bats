#!/usr/bin/env bats
load test_helper

@test "edita a entrada selecionada" {
  run run_tui edit
  [ "$status" -eq 0 ]
  assert_log_has 'edit personal example/login'
}

@test "falha da CLI nao encerra a TUI nem fica presa no pseudo-terminal" {
  run env MOCK_ACTION_EXIT=17 bash -c 'source "$1"; run_tui edit-fail' _ "$BATS_TEST_DIRNAME/test_helper.bash"
  [ "$status" -eq 0 ]
  assert_log_has 'edit personal example/login'
}
