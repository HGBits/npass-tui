#!/usr/bin/env bats
load test_helper

@test "exclusão exige confirmação explícita e não usa force" {
  run_tui_case delete
  [ "$status" -eq 0 ]
  assert_log_has 'rm personal example/login'
  run grep -Eq '^rm .* (-f|--force)( |$)' "$LOG"
  [ "$status" -ne 0 ]
}

@test "cancelar exclusão não chama npass rm" {
  run_tui_case delete-cancel
  [ "$status" -eq 0 ]
  run grep -Eq '^rm ' "$LOG"
  [ "$status" -ne 0 ]
}
@test "confirmação de exclusão sanitiza identidade e caminho antes de exibi-los" {
  MOCK_IDENTITY_CONTROL=1 MOCK_PATH_CONTROL=1 run_tui_case delete-control
  [ "$status" -eq 0 ]
  run grep -Eq '^rm ' "$LOG"
  [ "$status" -ne 0 ]
}
