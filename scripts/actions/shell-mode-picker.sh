#!/bin/bash
# shell-mode-picker.sh — Fuzzel-based interactive shell mode picker
# Keybinding: Super+S

set -euo pipefail

CFG="$HOME/.config/ocws/mode"
mkdir -p "$(dirname "$CFG")"

CURRENT="$(cat "$CFG" 2>/dev/null || echo noctalia)"

# Define available modes with descriptions
declare -A MODES=(
    ["dms"]="  Dank Material Shell — Integrated shell (default)"
    ["noctalia"]="  Noctalia Shell — Full-featured shell"
    ["sfwbar-plus"]="  OCWS Full — Dual panel with dock, desktop widgets, all features"
    ["sfwbar"]="  OCWS Minimal — Single top panel, lightweight"
    ["crystal"]="  Crystal Dock — External dock"
)

# Build fuzzel input: current mode marker + all modes
OPTIONS=""
for mode in "dms" "noctalia" "sfwbar-plus" "sfwbar" "crystal"; do
    desc="${MODES[$mode]}"
    if [ "$mode" = "$CURRENT" ]; then
        OPTIONS="${OPTIONS} [active] ${desc}\n"
    else
        OPTIONS="${OPTIONS} ${desc}\n"
    fi
done

# Launch fuzzel dmenu mode
SELECTED=$(echo -e "$OPTIONS" | fuzzel --dmenu \
    --prompt="Shell Mode: " \
    --width=50 \
    --lines=6 \
    --font="Noto Sans:size=14" \
    --layer=overlay \
    2>/dev/null)

# Extract mode name from selection
if [ -z "$SELECTED" ]; then
    # User cancelled
    exit 0
fi

# Parse the selected mode
NEW_MODE=""
case "$SELECTED" in
    *"Dank Material Shell"*) NEW_MODE="dms" ;;
    *"Noctalia"*)      NEW_MODE="noctalia" ;;
    *"OCWS Full"*)     NEW_MODE="sfwbar-plus" ;;
    *"OCWS Minimal"*)  NEW_MODE="sfwbar" ;;
    *"Crystal Dock"*)  NEW_MODE="crystal" ;;
    *) exit 1 ;;
esac

if [ -z "$NEW_MODE" ]; then
    exit 1
fi

# Skip if already active
if [ "$NEW_MODE" = "$CURRENT" ]; then
    notify-send -u low "Shell Mode" "Already using: $NEW_MODE" 2>/dev/null || true
    exit 0
fi

# Switch mode
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOGGLE_SHELL="$SCRIPT_DIR/../toggle-shell"

if [ -x "$TOGGLE_SHELL" ]; then
    "$TOGGLE_SHELL" "$NEW_MODE"
    notify-send -u low "Shell Mode" "Switched to: $NEW_MODE" 2>/dev/null || true
else
    notify-send -u critical "Shell Mode" "Error: toggle-shell not found" 2>/dev/null || true
    exit 1
fi
