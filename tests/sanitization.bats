#!/usr/bin/env bats
load test_helper

@test "sanitizador não produz erro de expressão do sed" {
  run run_tui create
  [ "$status" -eq 0 ]
  ! grep -Fq 'sed: -e expression' "$PTY_OUT"
}
