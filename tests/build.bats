#!/usr/bin/env bats
load test_helper

@test "release.sh gera bin/npass-tui executável, com sintaxe válida e autocontido" {
  run bash "$ROOT/release.sh" --no-sign
  [ "$status" -eq 0 ]
  [ -x "$TUI" ]
  [ "$(head -n 1 "$TUI")" = '#!/usr/bin/env bash' ]
  grep -q 'GENERATED FILE' "$TUI"
  bash -n "$TUI"
  # nada de carregar lib/ em tempo de execução
  run grep -nE '^[[:space:]]*(source|\.)[[:space:]]|NPASS_TUI_LIB' "$TUI"
  [ "$status" -ne 0 ]
}

@test "release.sh inclui todas as libs em ordem, com 99-main por último" {
  bash "$ROOT/release.sh" --no-sign >/dev/null
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

@test "install.sh não existe mais" {
  [ ! -e "$ROOT/install.sh" ]
}

@test "binário gerado roda copiado para fora do repositório" {
  bash "$ROOT/release.sh" --no-sign >/dev/null
  install -Dm755 "$TUI" "$TMP/dest/bin/npass-tui"
  run env NPASS_BIN="$MOCK_NPASS" "$TMP/dest/bin/npass-tui" </dev/null
  [ "$status" -eq 1 ]
  [[ $output == *"execute em um terminal interativo"* ]]
}

# Chave GPG descartável, num GNUPGHOME próprio: nunca toca o chaveiro real.
gpg_test_key() {
  export GNUPGHOME
  GNUPGHOME="$(mktemp -d /tmp/npass-tui-gpg.XXXXXX)"
  chmod 700 "$GNUPGHOME"
  gpg --batch --quiet --passphrase '' --quick-generate-key 'Teste Build <build@example.invalid>' ed25519 sign never 2>/dev/null
  TEST_KEY="$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}')"
  [ -n "$TEST_KEY" ]
}

gpg_test_cleanup() {
  [[ -n ${GNUPGHOME:-} ]] || return 0
  gpgconf --kill gpg-agent 2>/dev/null || true
  rm -rf -- "$GNUPGHOME"
}

teardown() { gpg_test_cleanup; }

@test "release.sh assina o binário com a chave informada e a assinatura verifica" {
  gpg_test_key
  run env NPASS_TUI_SIGN_KEY="$TEST_KEY" bash "$ROOT/release.sh"
  [ "$status" -eq 0 ]
  [ -s "$TUI.asc" ]
  head -n 1 "$TUI.asc" | grep -q 'BEGIN PGP SIGNATURE'
  run gpg --verify "$TUI.asc" "$TUI"
  [ "$status" -eq 0 ]
}

@test "release.sh --key tem precedência sobre NPASS_TUI_SIGN_KEY" {
  gpg_test_key
  run env NPASS_TUI_SIGN_KEY=chave-que-nao-existe bash "$ROOT/release.sh" --key="$TEST_KEY"
  [ "$status" -eq 0 ]
  [ -s "$TUI.asc" ]
}

@test "assinatura não verifica se o binário for alterado depois" {
  gpg_test_key
  env NPASS_TUI_SIGN_KEY="$TEST_KEY" bash "$ROOT/release.sh" >/dev/null
  echo '# adulterado' >>"$TUI"
  run gpg --verify "$TUI.asc" "$TUI"
  [ "$status" -ne 0 ]
}

@test "falha ao assinar preserva o binário e a assinatura válidos anteriores" {
  gpg_test_key
  env NPASS_TUI_SIGN_KEY="$TEST_KEY" bash "$ROOT/release.sh" >/dev/null
  local old_bin old_sig
  old_bin="$(sha256sum "$TUI" | cut -d' ' -f1)"
  old_sig="$(sha256sum "$TUI.asc" | cut -d' ' -f1)"

  run env NPASS_TUI_SIGN_KEY=chave-que-nao-existe bash "$ROOT/release.sh"
  [ "$status" -ne 0 ]
  [[ $output == *"falha ao assinar"* ]]
  [ "$(sha256sum "$TUI" | cut -d' ' -f1)" = "$old_bin" ]
  [ "$(sha256sum "$TUI.asc" | cut -d' ' -f1)" = "$old_sig" ]
  run gpg --verify "$TUI.asc" "$TUI"
  [ "$status" -eq 0 ]
}

@test "release.sh --no-sign remove assinatura antiga em vez de deixá-la órfã" {
  mkdir -p "$ROOT/bin"
  echo 'assinatura-velha' >"$TUI.asc"
  run bash "$ROOT/release.sh" --no-sign
  [ "$status" -eq 0 ]
  [ ! -e "$TUI.asc" ]
}

@test "release.sh rejeita opção desconhecida" {
  run bash "$ROOT/release.sh" --nada
  [ "$status" -ne 0 ]
  [[ $output == *"opção desconhecida"* ]]
}

@test "release.sh é o único entrypoint de build e build.sh não existe" {
  grep -Fq 'for f in lib/*.bash' "$ROOT/release.sh"
  grep -Fq 'gpg_args=(--batch --yes --armor --detach-sign' "$ROOT/release.sh"
  [ ! -e "$ROOT/build.sh" ]
}
