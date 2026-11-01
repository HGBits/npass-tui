#!/usr/bin/env bats
load test_helper

@test "nenhuma tecla se perde na fronteira do timeout de leitura" {
  MOCK_MANY=1 run_tui_case input-no-loss
  [ "$status" -eq 0 ]
}
