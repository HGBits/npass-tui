#!/usr/bin/env bats
load test_helper

@test "mover a seleção sem rolar redesenha só as duas linhas afetadas" {
  MOCK_MANY=1 run_tui_case render-nav
  [ "$status" -eq 0 ]
}

@test "rolar redesenha só a lista: header, rodapé e título não piscam" {
  MOCK_MANY=1 run_tui_case render-scroll
  [ "$status" -eq 0 ]
}

@test "navegar não executa npass show (conteúdo só com Enter explícito)" {
  MOCK_MANY=1 run_tui_case render-nav
  [ "$status" -eq 0 ]
  run grep -Eq '^show ' "$LOG"
  [ "$status" -ne 0 ]
}

@test "redimensionar repinta do zero sem corromper o layout" {
  MOCK_MANY=1 run_tui_case render-resize
  [ "$status" -eq 0 ]
}

@test "terminal pequeno demais: mensagem clara e nenhuma ação é disparada às cegas" {
  PTY_ROWS=8 PTY_COLS=30 run_tui_case render-too-small
  [ "$status" -eq 0 ]
  for cmd in rm edit insert clip otp show ls; do
    run grep -Eq "^$cmd " "$LOG"
    [ "$status" -ne 0 ]
  done
}

@test "depois de um comando externo a tela é repintada e o ruído da CLI some" {
  MOCK_ACTION_NOISE=1 run_tui_case render-external
  [ "$status" -eq 0 ]
}

@test "a TUI usa só atributos (bold, dim, reverse) e nenhuma cor própria" {
  run_tui_case render-attrs
  [ "$status" -eq 0 ]
}
