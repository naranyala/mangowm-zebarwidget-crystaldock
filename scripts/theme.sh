#!/bin/bash
#
# theme — Reactive theme switcher for labwc dotfiles
#
# Usage:
#   theme                          Show current theme
#   theme list                     List all themes with preview colors
#   theme set <name>               Apply theme by name
#   theme next                     Cycle to next theme
#   theme prev                     Cycle to previous theme
#   theme picker                   Interactive rofi picker
#   theme random                   Apply random theme
#   theme export [name]            Export theme to dotfiles/
#
# Keybind suggestions (add to rc.xml):
#   A-F12  → theme picker
#   A-S-F12 → theme next
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Find project root
PROJECT_DIR="$SCRIPT_DIR"
while [[ ! -d "$PROJECT_DIR/themes" && "$PROJECT_DIR" != "/" ]]; do
    PROJECT_DIR="$(dirname "$PROJECT_DIR")"
done
[[ -d "$PROJECT_DIR/themes" ]] || PROJECT_DIR="/media/naranyala/Data/projects-remote/labwc-crystaldock-barandwidgets"
THEMES_DIR="$PROJECT_DIR/themes"
STATE_DIR="$HOME/.config/labwc"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ============================================================
# State management
# ============================================================

get_current() {
    cat "$STATE_DIR/.current-theme" 2>/dev/null || echo ""
}

set_current() {
    mkdir -p "$STATE_DIR"
    echo "$1" > "$STATE_DIR/.current-theme"
}

get_history() {
    cat "$STATE_DIR/.theme-history" 2>/dev/null || echo ""
}

push_history() {
    local current
    current=$(get_current)
    [[ -n "$current" ]] || return
    local hist
    hist=$(get_history)
    # Add current to front, dedupe, keep last 20
    echo -e "${current}\n${hist}" | awk 'NF && !seen[$0]++' | head -20 > "$STATE_DIR/.theme-history"
}

# ============================================================
# Theme operations
# ============================================================

list_themes() {
    echo -e "${BOLD}Available themes:${NC}"
    echo ""
    for f in "$THEMES_DIR"/*.ini; do
        [[ -f "$f" ]] || continue
        local base name desc accent
        base=$(basename "$f" .ini)
        name=$(grep -m1 '^name=' "$f" 2>/dev/null | cut -d= -f2- | xargs)
        desc=$(grep -m1 '^description=' "$f" 2>/dev/null | cut -d= -f2- | xargs)
        accent=$(grep -m1 '^blue=' "$f" 2>/dev/null | cut -d= -f2- | xargs)
        [[ -z "$accent" ]] && accent=$(grep -m1 '^color_accent=' "$f" 2>/dev/null | cut -d= -f2- | xargs)

        local marker=" "
        [[ "$base" == "$(get_current)" ]] && marker="${GREEN}●${NC}"

        printf "  %b ${CYAN}%-18s${NC} %s\n" "$marker" "$base" "${name:-$base}"
        [[ -n "$desc" ]] && printf "  ${DIM}  %s${NC}\n" "$desc"
        [[ -n "$accent" ]] && printf "  ${DIM}  accent: %s${NC}\n" "$accent"
    done
    echo ""
    echo -e "  ${DIM}Use: theme set <name> | theme picker | theme next${NC}"
}

apply_theme() {
    local name="$1"
    local theme_file="$THEMES_DIR/${name}.ini"

    [[ -f "$theme_file" ]] || { echo -e "${RED}Theme not found: $name${NC}"; return 1; }

    # Use theme-engine if available
    if command -v theme-engine &>/dev/null; then
        theme-engine apply "$theme_file"
    else
        # Fallback: manual apply
        echo "theme-engine not found, manual apply not implemented"
        return 1
    fi

    set_current "$name"
    echo -e "${BOLD}Switched to: $name${NC}"
}

cycle_theme() {
    local direction="$1"  # next or prev
    local themes=()
    for f in "$THEMES_DIR"/*.ini; do
        [[ -f "$f" ]] && themes+=("$(basename "$f" .ini)")
    done

    local count=${#themes[@]}
    [[ $count -eq 0 ]] && { echo "No themes found"; return 1; }

    local current
    current=$(get_current)
    local idx=0

    # Find current index
    for i in "${!themes[@]}"; do
        [[ "${themes[$i]}" == "$current" ]] && idx=$i && break
    done

    # Calculate next index
    if [[ "$direction" == "next" ]]; then
        idx=$(( (idx + 1) % count ))
    else
        idx=$(( (idx - 1 + count) % count ))
    fi

    apply_theme "${themes[$idx]}"
}

picker_theme() {
    # Build choices with color previews
    local choices=()
    for f in "$THEMES_DIR"/*.ini; do
        [[ -f "$f" ]] || continue
        local base name accent
        base=$(basename "$f" .ini)
        name=$(grep -m1 '^name=' "$f" 2>/dev/null | cut -d= -f2- | xargs)
        accent=$(grep -m1 '^blue=' "$f" 2>/dev/null | cut -d= -f2- | xargs)
        [[ -z "$name" ]] && name="$base"
        choices+=("$name|$base|$accent")
    done

    # Build rofi input: "  ● name  (accent)"
    local current
    current=$(get_current)
    local rofi_input=""
    for choice in "${choices[@]}"; do
        IFS='|' read -r display_name key accent <<< "$choice"
        local marker=" "
        [[ "$key" == "$current" ]] && marker="●"
        rofi_input+="  $marker  $display_name  $accent\n"
    done

    # Launch rofi
    local selected
    selected=$(echo -e "$rofi_input" | rofi -dmenu -i \
        -p "Theme" \
        -theme-str 'window {width: 400px;}' \
        -theme-str 'listview {lines: 12;}' \
        -theme-str 'element {padding: 8px 12px;}' 2>/dev/null)

    [[ -z "$selected" ]] && return

    # Extract theme name from selection (strip marker and accent)
    local chosen_name
    chosen_name=$(echo "$selected" | sed 's/^[[:space:]]*[● ]*[[:space:]]*//' | awk '{print $1}' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

    # Find matching theme file
    for f in "$THEMES_DIR"/*.ini; do
        local base
        base=$(basename "$f" .ini)
        local file_name
        file_name=$(grep -m1 '^name=' "$f" 2>/dev/null | cut -d= -f2- | xargs | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

        if [[ "$base" == "$chosen_name" || "$file_name" == "$chosen_name" ]]; then
            apply_theme "$base"
            return
        fi
    done

    echo -e "${YELLOW}Could not match: $selected${NC}"
}

random_theme() {
    local themes=()
    for f in "$THEMES_DIR"/*.ini; do
        [[ -f "$f" ]] && themes+=("$(basename "$f" .ini)")
    done

    local count=${#themes[@]}
    [[ $count -eq 0 ]] && { echo "No themes found"; return 1; }

    local idx=$(( RANDOM % count ))
    apply_theme "${themes[$idx]}"
}

# ============================================================
# Main
# ============================================================

usage() {
    echo -e "${BOLD}theme${NC} — Reactive theme switcher"
    echo ""
    echo "Usage:"
    echo "  theme                    Show current theme"
    echo "  theme list               List all themes"
    echo "  theme set <name>         Apply theme"
    echo "  theme next               Cycle next"
    echo "  theme prev               Cycle previous"
    echo "  theme picker             Interactive rofi picker"
    echo "  theme random             Random theme"
    echo "  theme export [name]      Export to dotfiles/"
    echo ""
    echo "Examples:"
    echo "  theme set catppuccin-mocha"
    echo "  theme next"
    echo "  theme picker"
    echo ""
    echo "Keybind suggestion for rc.xml:"
    echo '  <keybind key="A-F12"><action name="Execute"><command>theme picker</command></action></keybind>'
    echo '  <keybind key="A-S-F12"><action name="Execute"><command>theme next</command></action></keybind>'
}

case "${1:-}" in
    list)    list_themes ;;
    set)     [[ -n "${2:-}" ]] || { echo "Usage: theme set <name>"; exit 1; }
             apply_theme "$2" ;;
    next)    cycle_theme next ;;
    prev)    cycle_theme prev ;;
    picker)  picker_theme ;;
    random)  random_theme ;;
    export)
        if [[ -n "${2:-}" ]]; then
            theme-engine export "$THEMES_DIR/${2}.ini"
        else
            theme-engine export "$THEMES_DIR/$(get_current).ini"
        fi
        ;;
    -h|--help|help) usage ;;
    "")
        current=$(get_current)
        if [[ -n "$current" ]]; then
            echo -e "Current theme: ${BOLD}$current${NC}"
        else
            echo -e "${YELLOW}No theme applied yet${NC}"
            echo -e "Run: ${BOLD}theme picker${NC} or ${BOLD}theme set <name>${NC}"
        fi
        ;;
    *)
        # Try direct name match
        if [[ -f "$THEMES_DIR/${1}.ini" ]]; then
            apply_theme "$1"
        else
            echo -e "${RED}Unknown command: $1${NC}"
            usage
            exit 1
        fi
        ;;
esac
