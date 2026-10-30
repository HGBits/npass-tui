#!/usr/bin/env bats
load test_helper

@test "split view: explorer ~40%, separador e junções alinhados, contexto da identidade" {
  run_tui_case layout-split
  [ "$status" -eq 0 ]
}

@test "terminal estreito: modo compacto mostra um painel por vez" {
  PTY_COLS=44 run_tui_case layout-compact
  [ "$status" -eq 0 ]
}

@test "limite do split: 49 colunas divide, 48 vira compacto, sem corromper" {
  PTY_COLS=49 run_tui_case layout-boundary
  [ "$status" -eq 0 ]
}

@test "locale sem UTF-8 usa bordas e símbolos ASCII" {
  PTY_LOCALE=C run_tui_case layout-ascii
  [ "$status" -eq 0 ]
}

@test "NPASS_TUI_ASCII=1 força o fallback ASCII em locale UTF-8" {
  NPASS_TUI_ASCII=1 run_tui_case layout-ascii
  [ "$status" -eq 0 ]
}

@test "voltar das entradas restaura a identidade que estava selecionada" {
  MOCK_TWO_IDS=1 run_tui_case layout-identity-cursor
  [ "$status" -eq 0 ]
}

@test "caminho acentuado longo é truncado por caractere, sem UTF-8 quebrado" {
  MOCK_PATH_ACCENT=1 PTY_COLS=60 run_tui_case layout-accent
  [ "$status" -eq 0 ]
}

@test "contexto da entrada acompanha a seleção, sem apagar nem executar show" {
  run_tui_case context-entry
  [ "$status" -eq 0 ]
  run grep -Eq '^show ' "$LOG"
  [ "$status" -ne 0 ]
}
