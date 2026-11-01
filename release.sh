#!/usr/bin/env bash
# Gera bin/npass-tui e assina somente com a chave oficial do NPASS.
#
# Uso:
#   ./release.sh                  gera e assina com a chave oficial
#   ./release.sh --key=ID         seleciona a chave privada (fingerprint ou ID)
#   ./release.sh --no-sign        só gera o binário (testes, CI)
#
# A chave pública oficial fica em packaging/npass-release.asc. A chave privada
# correspondente nunca deve ser armazenada neste repositório ou no CI.
# Seleção da chave privada: --key, NPASS_RELEASE_SIGNING_KEY,
# git config user.signingkey e, por último, a primeira chave secreta GPG.
#
# Verificar: gpg --verify bin/npass-tui.asc bin/npass-tui
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

sign=1
key="${NPASS_RELEASE_SIGNING_KEY:-}"
for arg in "$@"; do
	case "$arg" in
		--no-sign) sign=0 ;;
		--key=*) key="${arg#--key=}" ;;
		-h|--help)
			awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
			exit 0
			;;
		*) echo "release.sh: opção desconhecida: $arg" >&2; exit 2 ;;
	esac
done

out="bin/npass-tui"
sig="$out.asc"
mkdir -p "$(dirname "$out")"
tmp="$(mktemp "$out.XXXXXX")"
sig_tmp="$tmp.asc"
verify_home=""
cleanup() {
	rm -f -- "$tmp" "$sig_tmp"
	if [[ -n "$verify_home" ]]; then
		GNUPGHOME="$verify_home" gpgconf --kill all >/dev/null 2>&1 || true
		rm -rf -- "$verify_home"
	fi
}
trap cleanup EXIT

{
	echo '#!/usr/bin/env bash'
	echo '# GENERATED FILE - built by release.sh from lib/*.bash. Do not edit directly.'
	for f in lib/*.bash; do
		cat "$f"
		echo
	done
} >"$tmp"
bash -n "$tmp"
chmod 755 "$tmp"

if [[ $sign -eq 1 ]]; then
	command -v gpg >/dev/null 2>&1 || {
		echo "release.sh: gpg não encontrado; use --no-sign apenas para build local/testes." >&2
		exit 1
	}
	pubkey="packaging/npass-release.asc"
	[[ -s "$pubkey" && ! -L "$pubkey" ]] || {
		echo "release.sh: chave pública oficial ausente ou inválida: $pubkey" >&2
		exit 1
	}

	verify_home="$(mktemp -d "${TMPDIR:-/tmp}/npass-tui-verify.XXXXXX")"
	chmod 700 "$verify_home"
	if ! GNUPGHOME="$verify_home" gpg --batch --quiet --import "$pubkey"; then
		echo "release.sh: não foi possível importar a chave pública oficial." >&2
		exit 1
	fi
	pub_count="$(GNUPGHOME="$verify_home" gpg --batch --with-colons --list-keys 2>/dev/null | grep -c '^pub:' || true)"
	expected_fpr="$(GNUPGHOME="$verify_home" gpg --batch --with-colons --list-keys 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')"
	[[ "$pub_count" == 1 && "$expected_fpr" =~ ^[A-Fa-f0-9]{40,64}$ ]] || {
		echo "release.sh: a chave pública oficial deve conter exatamente uma chave primária válida." >&2
		exit 1
	}

	if [[ -z "$key" ]] && command -v git >/dev/null 2>&1; then
		key="$(git config --get user.signingkey 2>/dev/null || true)"
	fi
	if [[ -z "$key" ]]; then
		key="$(gpg --batch --with-colons --list-secret-keys 2>/dev/null | awk -F: '$1=="sec"{want=1;next} want && $1=="fpr"{print $10;exit}')"
	fi
	[[ -n "$key" ]] || {
		echo "release.sh: nenhuma chave privada GPG encontrada." >&2
		exit 1
	}
	secret_fpr="$(gpg --batch --with-colons --list-secret-keys "$key" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}' || true)"
	[[ -n "$secret_fpr" && "$secret_fpr" == "$expected_fpr" ]] || {
		echo "release.sh: a chave privada selecionada não corresponde à chave pública oficial ($expected_fpr)." >&2
		exit 1
	}

	if [[ -z ${GPG_TTY:-} ]] && tty_path="$(tty 2>/dev/null)"; then
		export GPG_TTY="$tty_path"
	fi
	if ! gpg --batch --yes --no-tty --armor --detach-sign --local-user "$expected_fpr" --output "$sig_tmp" "$tmp"; then
		echo "release.sh: falha ao assinar com a chave oficial." >&2
		exit 1
	fi
	status="$(GNUPGHOME="$verify_home" gpg --batch --no-auto-key-retrieve --status-fd=1 --verify "$sig_tmp" "$tmp" 2>/dev/null)" || {
		echo "release.sh: assinatura temporária não verifica com a chave oficial." >&2
		exit 1
	}
	valid_line="$(grep '^\[GNUPG:\] VALIDSIG ' <<<"$status" | head -n1)"
	read -r -a valid_fields <<<"$valid_line"
	signing_fpr="${valid_fields[11]:-${valid_fields[2]:-}}"
	[[ "$signing_fpr" == "$expected_fpr" ]] || {
		echo "release.sh: assinatura feita por uma chave inesperada." >&2
		exit 1
	}
fi

# Só publica o binário e a assinatura depois de todas as validações.
mv -f -- "$tmp" "$out"
if [[ $sign -eq 1 ]]; then
	mv -f -- "$sig_tmp" "$sig"
	echo "signed: $sig"
	echo "fingerprint: $expected_fpr"
else
	rm -f -- "$sig"
	echo "assinatura ignorada (--no-sign)"
fi
echo "built: $out"
