#!/usr/bin/env bats
load test_helper

@test "C abre o menu; Senha é o padrão e chama npass clip ID CAMINHO" {
  run_tui_case copy-password
  [ "$status" -eq 0 ]
  assert_log_has 'clip personal example/login'
}

@test "campo escolhido vai antes do ID: npass clip CAMPO ID CAMINHO" {
  run_tui_case copy-field
  [ "$status" -eq 0 ]
  assert_log_has 'clip login personal example/login'
  assert_log_has 'clip pin personal example/login'
}

@test "OTP é copiado por npass otp clip; o código nunca é pedido nem exibido" {
  run_tui_case copy-otp
  [ "$status" -eq 0 ]
  assert_log_has 'otp clip personal example/login'
  run grep -Eq '^otp personal' "$LOG"
  [ "$status" -ne 0 ]
}

@test "documento inteiro usa o campo all" {
  run_tui_case copy-all
  [ "$status" -eq 0 ]
  assert_log_has 'clip all personal example/login'
}

@test "outro campo: aceita nome válido, recusa nome com traço inicial e cancela se vazio" {
  run_tui_case copy-other
  [ "$status" -eq 0 ]
  assert_log_has 'clip api-key personal example/login'
  run grep -Fq -- '--help' "$LOG"
  [ "$status" -ne 0 ]
  [ "$(grep -Ec '^clip ' "$LOG")" -eq 1 ]
}

@test "a tecla O não faz mais nada e npass otp nunca é chamado" {
  run_tui_case copy-no-otp-key
  [ "$status" -eq 0 ]
  run grep -Eq '^otp' "$LOG"
  [ "$status" -ne 0 ]
}

@test "Esc cancela o menu sem executar nada" {
  run_tui_case copy-menu-layout
  [ "$status" -eq 0 ]
  run grep -Eq '^(clip|otp)' "$LOG"
  [ "$status" -ne 0 ]
}

@test "C na lista de entradas não faz nada: copiar só depois de abrir a entrada" {
  run_tui_case copy-not-in-list
  [ "$status" -eq 0 ]
  run grep -Eq '^(clip|otp)' "$LOG"
  [ "$status" -ne 0 ]
}

@test "sessão Wayland usa o clip do core, sem aviso de destino" {
  run_tui_case copy-no-note
  [ "$status" -eq 0 ]
  run_tui_case copy-password
  assert_log_has 'clip personal example/login'
  run grep -Fq 'xclip' "$LOG"
  [ "$status" -ne 0 ]
}

@test "sessão X11 com a extensão instalada usa clip-x11 para senha, campo e documento" {
  MOCK_SESSION=x11 MOCK_EXPECT_NOTE='clip-x11 (sessão X11)' run_tui_case copy-backend-note
  [ "$status" -eq 0 ]
  MOCK_SESSION=x11 run_tui_case copy-field
  [ "$status" -eq 0 ]
  assert_log_has 'clip-x11 login personal example/login'
  assert_log_has 'clip-x11 pin personal example/login'
  MOCK_SESSION=x11 run_tui_case copy-all
  assert_log_has 'clip-x11 all personal example/login'
  MOCK_SESSION=x11 run_tui_case copy-password
  assert_log_has 'clip-x11 personal example/login'
}

@test "em X11 o OTP continua em npass otp clip (a extensão não cobre OTP)" {
  MOCK_SESSION=x11 run_tui_case copy-otp
  [ "$status" -eq 0 ]
  assert_log_has 'otp clip personal example/login'
  run grep -Eq '^clip-x11' "$LOG"
  [ "$status" -ne 0 ]
}

@test "X11 sem a extensão clip-x11: usa clip e avisa como resolver" {
  MOCK_SESSION=x11 MOCK_EXT_NOCLIP=1 MOCK_CLIP_FAIL=1 run_tui_case copy-x11-missing
  [ "$status" -eq 0 ]
  assert_log_has 'clip personal example/login'
}

@test "NPASS_TUI_CLIP força o backend e é anotado no menu" {
  MOCK_CLIP_OVERRIDE=wclip MOCK_EXPECT_NOTE='wclip (NPASS_TUI_CLIP)' run_tui_case copy-backend-note
  [ "$status" -eq 0 ]
  MOCK_CLIP_OVERRIDE=wclip run_tui_case copy-password
  assert_log_has 'wclip personal example/login'
}

@test "NPASS_TUI_CLIP com valor desconhecido é ignorado" {
  MOCK_CLIP_OVERRIDE='evil;rm' run_tui_case copy-password
  [ "$status" -eq 0 ]
  assert_log_has 'clip personal example/login'
}

@test "NPASS_TUI_CLIP=clip-x11 é rejeitado como valor desconhecido" {
  MOCK_CLIP_OVERRIDE=clip-x11 run_tui_case copy-password
  [ "$status" -eq 0 ]
  assert_log_has 'clip personal example/login'
}

@test "X11 com clip-x11 recusada pelo npass: avisa no menu e na falha, sem usar a extensão" {
  MOCK_SESSION=x11 MOCK_EXT_REFUSED=1 MOCK_CLIP_FAIL=1 run_tui_case copy-x11-refused
  [ "$status" -eq 0 ]
  assert_log_has 'clip personal example/login'
  run grep -Eq '^clip-x11' "$LOG"
  [ "$status" -ne 0 ]
}
