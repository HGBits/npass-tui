#!/usr/bin/env bats
load test_helper

@test "build.sh gera bin/npass-tui executável, com sintaxe válida e autocontido" {
  run bash "$ROOT/build.sh"
  [ "$status" -eq 0 ]
  [ -x "$TUI" ]
  [ "$(head -n 1 "$TUI")" = '#!/usr/bin/env bash' ]
  grep -q 'GENERATED FILE' "$TUI"
  bash -n "$TUI"
  # nada de carregar lib/ em tempo de execução
  run grep -nE '^[[:space:]]*(source|\.)[[:space:]]|NPASS_TUI_LIB' "$TUI"
  [ "$status" -ne 0 ]
}

@test "build.sh inclui todas as libs em ordem, com 99-main por último" {
  bash "$ROOT/build.sh" >/dev/null
  local prev=0 f marker line
  for f in "$ROOT"/lib/*.bash; do
    marker=$(grep -v '^[[:space:]]*$' "$f" | head -n 1)
    line=$(grep -nF -- "$marker" "$TUI" | head -n 1 | cut -d: -f1)
    [ -n "$line" ]
    (( line > prev ))
    prev=$line
  done
  grep -q '^main "\$@"$' "$TUI"
}

@test "bin/ não é versionado" {
  grep -qx 'bin/' "$ROOT/.gitignore"
}

@test "install.sh instala o arquivo único e o binário instalado roda sem o repositório" {
  local prefix="$TMP/prefix"
  run env PREFIX="$prefix" bash "$ROOT/install.sh"
  [ "$status" -eq 0 ]
  [ -x "$prefix/bin/npass-tui" ]
  [ "$(stat -c %a "$prefix/bin/npass-tui")" = "755" ]
  [ ! -e "$prefix/share/npass-tui" ]
  # sem terminal interativo, chega até a checagem de TTY (prova que o arquivo é autocontido)
  run env NPASS_BIN="$MOCK_NPASS" "$prefix/bin/npass-tui" </dev/null
  [ "$status" -eq 1 ]
  [[ $output == *"execute em um terminal interativo"* ]]
}

@test "install.sh --uninstall remove o binário" {
  local prefix="$TMP/prefix"
  env PREFIX="$prefix" bash "$ROOT/install.sh" >/dev/null
  run env PREFIX="$prefix" bash "$ROOT/install.sh" --uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$prefix/bin/npass-tui" ]
}
