#!/usr/bin/env bash
# Punto de entrada de la actividad 3; ejecutar desde server4 como ubuntu.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec bash "$HERE/../comun/orquestar.sh" 3 "${@}"
