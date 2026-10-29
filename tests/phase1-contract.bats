#!/usr/bin/env bats
load test_helper


@test "versão incompatível (major diferente) aborta com mensagem clara" {
  run bash -c "source '$ROOT/lib/00-core.bash' 2>/dev/null; source '$ROOT/lib/02-backend.bash'; APP_NAME=t NPASS_BIN='$MOCK_NPASS' NPASS_LOG=/dev/null MOCK_VERSION=3.0 check_npass_version"
  [ "$status" -ne 0 ]
  [[ $output == *incompatível* ]]
}

@test "versão abaixo do mínimo aborta" {
  run bash -c "source '$ROOT/lib/02-backend.bash'; APP_NAME=t NPASS_BIN='$MOCK_NPASS' NPASS_LOG=/dev/null MOCK_VERSION=2.7 check_npass_version"
  [ "$status" -ne 0 ]
}

@test "versão 2.8 e superiores na mesma major passam" {
  run bash -c "source '$ROOT/lib/02-backend.bash'; APP_NAME=t NPASS_BIN='$MOCK_NPASS' NPASS_LOG=/dev/null MOCK_VERSION=2.9 check_npass_version"
  [ "$status" -eq 0 ]
}

@test "saída de help não reconhecível aborta, salvo override" {
  run bash -c "source '$ROOT/lib/02-backend.bash'; APP_NAME=t NPASS_BIN='$MOCK_NPASS' NPASS_LOG=/dev/null MOCK_VERSION=xyz check_npass_version"
  [ "$status" -ne 0 ]
  run bash -c "source '$ROOT/lib/02-backend.bash'; NPASS_TUI_SKIP_VERSION_CHECK=1 APP_NAME=t NPASS_BIN='$MOCK_NPASS' NPASS_LOG=/dev/null MOCK_VERSION=xyz check_npass_version"
  [ "$status" -eq 0 ]
}
