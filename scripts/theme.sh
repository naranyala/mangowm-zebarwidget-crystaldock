#!/bin/bash
#
# theme — Quick theme switcher for labwc desktop
#
# Usage:
#   theme                    List available themes
#   theme <name>             Apply theme by name
#   theme current            Show active theme
#   theme next               Cycle to next theme
#   theme preview <name>     Preview theme without applying
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || echo "")"
THEMES_DIR="${PROJECT_DIR:-/media/naranyala/Data/projects-remote/labwc-crystaldock-barandwidgets}/themes"
CURRENT_FILE="$HOME/.config/labwc/.current-theme"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}✓${NC} $1"; }
info()  { echo -e "  ${CYAN}→${NC} $1"; }

# Get list of themes
get_themes() {
  for f in "$THEMES_DIR"/*.ini; do
    [[ -f "$f" ]] || continue
    basename "$f" .ini
  done | sort
}

# Get current theme
get_current() {
  if [[ -f "$CURRENT_FILE" ]]; then
    cat "$CURRENT_FILE"
  else
    echo "none"
  fi
}

# Apply theme
apply_theme() {
  local name="$1"
  local theme_file="$THEMES_DIR/${name}.ini"

  if [[ ! -f "$theme_file" ]]; then
    echo -e "${RED}✗ Theme not found: $name${NC}"
    echo "Available themes:"
    get_themes | sed 's/^/  /'
    exit 1
  fi

  echo -e "${BOLD}Applying: $name${NC}"
  bash "$SCRIPT_DIR/theme-engine.sh" apply "$theme_file"

  # Reload labwc
  if pidof labwc &>/dev/null; then
    kill -SIGHUP "$(pidof labwc)" 2>/dev/null && \
      pass "labwc reloaded" || true
  fi

  # Restart sfwbar
  if pidof sfwbar &>/dev/null; then
    killall sfwbar 2>/dev/null
    sleep 0.3
    sfwbar &>/dev/null &
    disown
    pass "sfwbar restarted"
  fi

  echo ""
  echo -e "${GREEN}${BOLD}Theme applied: $name${NC}"
}

# Cycle to next theme
next_theme() {
  local current
  current=$(get_current)
  local themes=()
  while IFS= read -r t; do
    themes+=("$t")
  done < <(get_themes)

  if [[ ${#themes[@]} -eq 0 ]]; then
    echo "No themes found"
    exit 1
  fi

  local idx=0
  for i in "${!themes[@]}"; do
    if [[ "${themes[$i]}" == "$current" ]]; then
      idx=$i
      break
    fi
  done

  local next_idx=$(( (idx + 1) % ${#themes[@]} ))
  apply_theme "${themes[$next_idx]}"
}

# Main
case "${1:-}" in
  list|"")
    echo -e "${BOLD}Available themes:${NC}"
    echo ""
    current_theme=$(get_current)
    while IFS= read -r name; do
      if [[ "$name" == "$current_theme" ]]; then
        echo -e "  ${GREEN}●${NC} $name ${CYAN}(active)${NC}"
      else
        echo -e "  ${DIM}○${NC} $name"
      fi
    done < <(get_themes)
    echo ""
    echo "Usage: theme <name> | theme next | theme current"
    ;;
  current)
    echo "Active theme: $(get_current)"
    ;;
  next)
    next_theme
    ;;
  preview)
    [[ -n "${2:-}" ]] || { echo "Usage: theme preview <name>"; exit 1; }
    bash "$SCRIPT_DIR/theme-engine.sh" preview "$THEMES_DIR/${2}.ini"
    ;;
  *)
    apply_theme "$1"
    ;;
esac
