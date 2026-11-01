#!/usr/bin/env bash
# Gera bin/npass-tui (arquivo único) a partir de lib/*.bash, em ordem, e assina
# o binário com GPG (assinatura destacada em bin/npass-tui.asc).
#
# Uso:
#   ./build.sh                  gera e assina com a chave padrão
#   ./build.sh --key=ID         assina com a chave ID (fingerprint ou e-mail)
#   ./build.sh --no-sign        só gera o binário (testes, CI)
# Chave: --key, depois NPASS_TUI_SIGN_KEY, depois `git config user.signingkey`,
# depois a chave secreta padrão do gpg.
#
# bin/ está no .gitignore; os testes reconstroem com --no-sign quando preciso.
# Verificar: gpg --verify bin/npass-tui.asc bin/npass-tui
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

sign=1
key="${NPASS_TUI_SIGN_KEY:-}"

for arg in "$@"; do
	case "$arg" in
	--no-sign) sign=0 ;;
	--key=*) key="${arg#--key=}" ;;
	-h | --help)
		awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
		exit 0
		;;
	*)
		echo "build.sh: opção desconhecida: $arg" >&2
		exit 1
		;;
	esac
done

out="bin/npass-tui"
sig="$out.asc"
mkdir -p "$(dirname "$out")"

tmp="$(mktemp "$out.XXXXXX")"
sig_tmp="$tmp.asc"
cleanup() { rm -f -- "$tmp" "$sig_tmp"; }
trap cleanup EXIT

{
	echo '#!/usr/bin/env bash'
	echo '# GENERATED FILE - built by build.sh from lib/*.bash. Do not edit directly.'
	for f in lib/*.bash; do
		cat "$f"
		echo
	done
} >"$tmp"
bash -n "$tmp"
chmod 755 "$tmp"

if [[ $sign -eq 1 ]]; then
	if ! command -v gpg >/dev/null 2>&1; then
		echo "build.sh: gpg não encontrado; use --no-sign para gerar sem assinar." >&2
		exit 1
	fi

	if [[ -z $key ]] && command -v git >/dev/null 2>&1; then
		key="$(git config --get user.signingkey 2>/dev/null || true)"
	fi

	if [[ -z ${GPG_TTY:-} ]] && tty_path="$(tty 2>/dev/null)"; then
		export GPG_TTY="$tty_path"
	fi

	gpg_args=(--batch --yes --armor --detach-sign --output "$sig_tmp")
	[[ -n $key ]] && gpg_args+=(--local-user "$key")

	if ! gpg "${gpg_args[@]}" "$tmp"; then
		echo "build.sh: falha ao assinar o binário temporário." >&2
		exit 1
	fi
	if ! gpg --verify "$sig_tmp" "$tmp" >/dev/null 2>&1; then
		echo "build.sh: assinatura temporária não verifica." >&2
		exit 1
	fi
fi

# Só substitui os artefatos anteriores depois de build e assinatura válidos.
mv -f -- "$tmp" "$out"
if [[ $sign -eq 1 ]]; then
	mv -f -- "$sig_tmp" "$sig"
	echo "signed: $sig"
else
	rm -f -- "$sig"
	echo "assinatura ignorada (--no-sign)"
fi
echo "built: $out"
