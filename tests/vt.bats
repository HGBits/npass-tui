#!/usr/bin/env bats
load test_helper

@test "emulador de terminal dos testes PTY passa nos seus próprios testes" {
  run python3 "$ROOT/tests/test_vt.py"
  if (( status != 0 )); then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
}
