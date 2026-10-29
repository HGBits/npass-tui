#!/usr/bin/env bash
# Instala o npass-tui. Reconstrói bin/npass-tui a partir de lib/*.bash e
# instala o arquivo único (sem lib/ em tempo de execução), como o npass-store.
#
# Uso:
#   sudo ./install.sh                      instala em /usr/bin/npass-tui
#   ./install.sh --prefix=$HOME/.local     instala só para você
#   ./install.sh --bindir=/caminho/bin     escolhe o diretório do binário
#   ./install.sh --uninstall               remove o binário instalado
# Variáveis: PREFIX (padrão /usr), BINDIR, DESTDIR (empacotamento).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

: "${PREFIX:=/usr}"
: "${BINDIR:=}"
: "${DESTDIR:=}"
uninstall=0

for arg in "$@"; do
	case "$arg" in
	--uninstall) uninstall=1 ;;
	--prefix=*) PREFIX="${arg#--prefix=}" ;;
	--bindir=*) BINDIR="${arg#--bindir=}" ;;
	-h | --help)
		awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
		exit 0
		;;
	*)
		echo "install.sh: opção desconhecida: $arg" >&2
		exit 1
		;;
	esac
done

bindir="$DESTDIR${BINDIR:-$PREFIX/bin}"
target="$bindir/npass-tui"

if [[ $uninstall -eq 1 ]]; then
	if [[ -e "$target" ]]; then
		rm -f -- "$target"
		echo "removido: $target"
	else
		echo "nada instalado em $bindir para remover."
	fi
	exit 0
fi

if [[ -z "$DESTDIR" && $EUID -ne 0 ]]; then
	probe="$bindir"
	while [[ ! -d "$probe" && "$probe" != "/" ]]; do probe="$(dirname "$probe")"; done
	if [[ ! -w "$probe" ]]; then
		echo "install.sh: sem permissão de escrita em $bindir. Rode com sudo, ou use --prefix=\$HOME/.local para instalar só para você." >&2
		exit 1
	fi
fi

echo "Reconstruindo bin/npass-tui a partir de lib/*.bash..."
bash build.sh

old_umask="$(umask)"
umask 022
mkdir -p "$bindir"
install -m 755 bin/npass-tui "$target"
umask "$old_umask"
echo "instalado: $target"
