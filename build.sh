#!/usr/bin/env bash
# Gera bin/npass-tui (arquivo único) a partir de lib/*.bash, em ordem.
# bin/ está no .gitignore; install.sh e os testes reconstroem quando preciso.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

out="bin/npass-tui"
mkdir -p "$(dirname "$out")"
{
	echo '#!/usr/bin/env bash'
	echo '# GENERATED FILE - built by build.sh from lib/*.bash. Do not edit directly.'
	for f in lib/*.bash; do
		cat "$f"
		echo
	done
} >"$out"
bash -n "$out"
chmod +x "$out"
echo "built: $out"
