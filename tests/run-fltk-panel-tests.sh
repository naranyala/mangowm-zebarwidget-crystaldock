#!/bin/bash
# FLTK Panel Test Suite Runner
# Runs test-fltk-panel.sh and reports result

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if "$SCRIPT_DIR/test-fltk-panel.sh"; then
    exit 0
else
    exit 1
fi
