#!/usr/bin/env bash
# Canonical release entrypoint. Keep build implementation in build.sh.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/build.sh" "$@"
