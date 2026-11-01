#!/usr/bin/env bash
# Compatibilidade com chamadas antigas. A lógica de build e assinatura vive em release.sh.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/release.sh" "$@"
