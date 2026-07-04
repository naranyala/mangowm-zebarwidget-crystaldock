#!/bin/bash
#
# workspace.sh — Advanced workspace/desktop actions with preset management
#
# Modes: switch, move, list, next, prev, preset, save, load

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR=""
WORKSPACE_PRESETS_DIR="$HOME/.config/ocws/workspaces"

# Find project root
if [[ -d "$SCRIPT_DIR/.." ]]; then
    PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
elif [[ -d "/media/naranyala/Data/projects-remote/labwc-fuzzel-sfwbar/scripts" ]]; then
    PROJECT_DIR="/media/naranyala/Data/projects-remote/labwc-fuzzel-sfwbar"
fi

MODE="${1:-list}"
TARGET="${2:-}"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'
RED='\033[0;31m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo -e "${CYAN}→${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

# Load workspace presets if available
source_workspace_presets() {
    local preset_script="$PROJECT_DIR/scripts/workspace-presets.sh"
    if [[ -f "$preset_script" ]]; then
        source "$preset_script"
    fi
}

switch_workspace() {
    local ws="${1:-1}"
    # Alt+1-9 switches workspace in labwc
    if command -v xdotool >/dev/null 2>&1; then
        xdotool key --clearmodifiers alt+"$ws" 2>/dev/null || true
    else
        echo "xdotool not available, cannot switch workspace manually"
    fi
    pass "Switched to workspace $ws"
}

move_to_workspace() {
    local ws="${1:-1}"
    # Super+Shift+1-9 moves window
    if command -v xdotool >/dev/null 2>&1; then
        xdotool key --clearmodifiers super+shift+"$ws" 2>/dev/null || true
    else
        echo "xdotool not available, cannot move window to workspace manually"
    fi
    pass "Moved window to workspace $ws"
}

next_workspace() {
    # Alt+Tab or similar for next workspace
    if command -v xdotool >/dev/null 2>&1; then
        # Simplified: just go to next workspace
        xdotool key --clearmodifiers alt+Right 2>/dev/null || true
    fi
    pass "Next workspace"
}

prev_workspace() {
    if command -v xdotool >/dev/null 2>&1; then
        xdotool key --clearmodifiers alt+Left 2>/dev/null || true
    fi
    pass "Previous workspace"
}

list_workspaces() {
    echo ""
    echo "Workspaces: 1-9"
    echo ""
    echo "Switch: Alt + [1-9]"
    echo "Move window: Super + Shift + [1-9]"
    echo ""
    
    # List preset workspaces if available
    if [[ -d "$WORKSPACE_PRESETS_DIR" ]]; then
        echo "Workspace Presets:"
        local index=1
        for preset in "$WORKSPACE_PRESETS_DIR"/*.json; do
            [[ -f "$preset" ]] || continue
            
            local name=$(grep -o '"name": "[^"]*"' "$preset" | sed 's/"name": "//;s/"//')
            local desc=$(grep -o '"description": "[^"]*"' "$preset" | sed 's/"description": "//;s/"//')
            
            echo "  ${CYAN}$index.${NC} preset: $name - $desc"
            ((index++))
        done
        echo ""
        if [[ $index -gt 1 ]]; then
            echo "Load a preset with: $0 preset <name>"
        fi
    fi
}

load_workspace_preset() {
    local preset_name="$1"
    
    if [[ -z "$preset_name" ]]; then
        fail "Please provide a preset name"
    fi
    
    local preset_file="$WORKSPACE_PRESETS_DIR/$preset_name.json"
    
    if [[ ! -f "$preset_file" ]]; then
        fail "Workspace preset not found: $preset_name"
    fi
    
    info "Loading workspace preset: $preset_name"
    
    # Parse preset for workspace number
    local ws_number=$(grep -o '"workspace": {[^}]*\"number\": \([0-9]*\)' "$preset_file" | sed 's/.*\"number\": \([0-9]*\).*/\1/')
    
    if [[ -z "$ws_number" ]]; then
        warn "No workspace number found in preset, using default"
        ws_number=1
    fi
    
    # Switch to the preset workspace
    switch_workspace "$ws_number"
    
    info "Workspace preset '$preset_name' applied (workspace $ws_number)"
    info "Also edit $preset_file manually to apply theme and keybinding changes"
}

create_workspace_preset() {
    local name="$1"
    local description="$2"
    
    source_workspace_presets
    
    if [[ -z "$name" ]]; then
        fail "Please provide a preset name"
    fi
    
    save_workspace "$name" "$description"
}

case "$MODE" in
  switch|goto|go)
    if [ -n "$TARGET" ]; then
      switch_workspace "$TARGET"
    else
      list_workspaces
    fi
    ;;
  move|send)
    if [ -n "$TARGET" ]; then
      move_to_workspace "$TARGET"
    else
      list_workspaces
    fi
    ;;
  next)
    next_workspace
    ;;
  prev|previous)
    prev_workspace
    ;;
  list|ls)
    list_workspaces
    ;;
  preset)
    if [ -n "$TARGET" ]; then
      load_workspace_preset "$TARGET"
    else
      info "Usage: $0 preset <name>"
      list_workspaces
    fi
    ;;
  save|create)
    source_workspace_presets
    if [ -n "$TARGET" ]; then
      save_workspace "$TARGET" "$3"
    else
      info "Usage: $0 save <name> <description>"
      info "Available command: $0 list"
    fi
    ;;
  help|--help|-h|*)
    echo ""
    echo "Advanced Workspace Management"
    echo ""
    echo "Usage: $0 <command> [target] [description]"
    echo ""
    echo "Basic Workspace Commands:"
    echo "  switch <N>     Switch to workspace N"
    echo "  move <N>       Move window to workspace N"
    echo "  next           Next workspace"
    echo "  prev           Previous workspace"
    echo "  list           List workspaces"
    echo ""
    echo "Workspace Preset Commands:"
    echo "  preset <name>  Load a workspace preset"
    echo "  save <name> <desc>  Create a workspace preset"
    echo ""
    echo "Examples:"
    echo "  $0 switch 2           Switch to workspace 2"
    echo "  $0 move 3             Move current window to workspace 3"
    echo "  $0 list               Show workspaces and presets"
    echo "  $0 preset dev-setup   Load dev setup preset"
    echo "  $0 save my-preset \"My custom workspace setup\""
    echo ""
    echo "Presets are stored in: ~/.config/ocws/workspaces/"
    echo ""
    ;;
esac
