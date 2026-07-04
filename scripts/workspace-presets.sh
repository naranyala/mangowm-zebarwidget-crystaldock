#!/bin/bash
# workspace-presets.sh — Advanced workspace management with save/load presets
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR=""
WORKSPACES_DIR="$HOME/.config/ocws/workspaces"

# Find project root
if [[ -d "/media/naranyala/Data/projects-remote/labwc-fuzzel-sfwbar/scripts" ]]; then
    PROJECT_DIR="/media/naranyala/Data/projects-remote/labwc-fuzzel-sfwbar"
elif [[ -d "$(dirname "$SCRIPT_DIR")/scripts" ]]; then
    PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
else
    echo "Error: Cannot find project root" >&2
    exit 1
fi

cd "$PROJECT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }

# Workspace preset management functions
create_preset() {
    local name="$1"
    local description="$2"
    
    mkdir -p "$WORKSPACES_DIR"
    
    local preset_file="$WORKSPACES_DIR/$name.json"
    
    # Current workspace state
    local current_desktop=$(grep -o '<number>[0-9]*</number>' dotfiles/labwc/rc.xml | head -1 | sed 's/<[a-zA-Z]*>//g')
    local decoration=$(grep -o '<decoration>[^<]*</decoration>' dotfiles/labwc/rc.xml | sed 's/<[a-zA-Z/]*>//g')
    
    # Build preset JSON
    cat > "$preset_file" << EOF
{
  "name": "$name",
  "description": "$description",
  "created": "$(date -Iseconds)",
  "workspace": {
    "number": ${current_desktop:-9},
    "firstdesk": 1
  },
  "theme": {
    "name": "Clearlooks",
    "fonts": {
      "ActiveWindow": {"name": "sans", "size": 10},
      "InactiveWindow": {"name": "sans", "size": 10},
      "MenuHeader": {"name": "sans", "size": 10},
      "MenuItem": {"name": "sans", "size": 10}
    }
  },
  "keybindings": {
    "common": [
      "A-r": "Reconfigure",
      "A-q": "Close",
      "A-space": "ShowMenu",
      "A-Return": "Execute foot",
      "A-a": "Execute fuzzel"
    ],
    "window_mgmt": [
      "A-f": "ToggleFullscreen",
      "W-a": "ToggleMaximize"
    ],
    "focus": [
      "A-Left": "Focus left",
      "A-Right": "Focus right",
      "A-Up": "Focus up",
      "A-Down": "Focus down"
    ]
  }
}
EOF
    
    pass "Created workspace preset: $name"
    echo "  Location: $preset_file"
}

list_presets() {
    echo -e "${BOLD}Available Workspace Presets:${NC}"
    echo ""
    
    if [[ ! -d "$WORKSPACES_DIR" ]] || [[ $(ls -A "$WORKSPACES_DIR" 2>/dev/null | wc -l) -eq 0 ]]; then
        echo -e "  ${DIM}No workspace presets found.${NC}"
        echo "  Use: $0 save <name> <description> to create one"
        return
    fi
    
    local index=1
    for preset in "$WORKSPACES_DIR"/*.json; do
        [[ -f "$preset" ]] || continue
        
        local name=$(grep -o '"name": "[^"]*"' "$preset" | sed 's/"name": "//;s/"//')
        local desc=$(grep -o '"description": "[^"]*"' "$preset" | sed 's/"description": "//;s/"//')
        local created=$(grep -o '"created": "[^"]*"' "$preset" | sed 's/"created": "//;s/"//')
        
        echo -e "  ${CYAN}$index.${NC} $name"
        echo -e "    $desc"
        echo -e "    Created: $created"
        echo -e "    File: ${preset#*$WORKSPACES_DIR/}"
        echo ""
        ((index++))
    done
}

save_workspace() {
    local name="$1"
    local description="$2"
    
    if [[ -z "$name" ]]; then
        fail "Please provide a preset name"
    fi
    
    create_preset "$name" "$description"
}

load_preset() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        fail "Please provide a preset name to load"
    fi
    
    local preset_file="$WORKSPACES_DIR/$name.json"
    
    if [[ ! -f "$preset_file" ]]; then
        fail "Workspace preset not found: $name"
    fi
    
    echo "Loading workspace preset: $name"
    
    # TODO: Implement actual workspace restoration
    # This would involve:
    # 1. Restoring rc.xml with preset settings
    # 2. Reloading labwc to apply changes
    # 3. Restoring window positions and states
    
    info "Preset loaded (manual restoration required)"
    info "Edit $preset_file manually to apply settings"
}

show_help() {
    cat << EOF
workspace-presets.sh — Advanced workspace management with save/load presets

Usage:
  workspace-presets.sh save <name> <description>    Create a workspace preset
  workspace-presets.sh load <name>                  Load a workspace preset
  workspace-presets.sh list                         List all presets
  workspace-presets.sh help|help                     Show this help

Commands:
  save    Create a snapshot of current workspace state (keybindings, theme, etc.)
  load    Restore a previously saved workspace configuration
  list    Display all available workspace presets

Examples:
  workspace-presets.sh save 'dev-setup' 'Development environment with terminal, editor, and monitors'
  workspace-presets.sh load 'browser-setup'
  workspace-presets.sh list

Presets are stored in: ~/.config/ocws/workspaces/
EOF
}

# Main command handling
main() {
    if [[ $# -lt 1 ]]; then
        show_help
        exit 1
    fi
    
    case "$1" in
        save|create)
            save_workspace "$2" "$3"
            ;;
        load)
            load_preset "$2"
            ;;
        list|ls)
            list_presets
            ;;
        help|--help|-h|"")
            show_help
            ;;
        *)
            fail "Unknown command: $1"
            ;;
    esac
}

# Execute main function with all arguments
main "$@"
