#!/bin/bash
# shell-switcher.sh — Switch between shell modes
# Used by autostart and can be called manually
# Config: ~/.config/ocws/mode (legacy: ~/.config/labwc-widgets/shell-mode)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOGGLE_SHELL="$SCRIPT_DIR/toggle-shell"

CFG="$HOME/.config/ocws/mode"
LEGACY_CFG="$HOME/.config/labwc-widgets/shell-mode"

# If no argument, read current mode
if [ -z "${1:-}" ]; then
    if [ -f "$CFG" ]; then
        MODE=$(cat "$CFG")
    elif [ -f "$LEGACY_CFG" ]; then
        MODE=$(cat "$LEGACY_CFG")
    else
        MODE="dms"
    fi
else
    MODE="$1"
fi

if [ -x "$TOGGLE_SHELL" ]; then
    exec "$TOGGLE_SHELL" "$MODE"
else
    echo "error: toggle-shell not found at $TOGGLE_SHELL"
    exit 1
fi
