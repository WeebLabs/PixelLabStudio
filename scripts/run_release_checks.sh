#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

"$SCRIPT_DIR/run_tests.sh"
"$SCRIPT_DIR/run_performance.sh"
"$SCRIPT_DIR/run_export_smoke.sh" "${1:-}"
