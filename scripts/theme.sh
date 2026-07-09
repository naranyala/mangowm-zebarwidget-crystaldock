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

# Centralized error handling + desktop notifications (ocws-notify / mako / dunst)
source "$SCRIPT_DIR/lib/ocws-err.sh"
ocws_enable_strict

PROJECT_DIR=""
# Walk up from script dir looking for themes/
_candidate="$SCRIPT_DIR"
while [[ "$_candidate" != "/" ]]; do
  if [[ -d "$_candidate/themes" ]]; then
    PROJECT_DIR="$_candidate"
    break
  fi
  _candidate="$(dirname "$_candidate")"
done

[[ -d "$PROJECT_DIR/themes" ]] || ocws_die "Cannot find themes/ directory"
THEMES_DIR="$PROJECT_DIR/themes"
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
    ocws_die "Theme not found: $name"
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

  # Restart crystal-dock
  if pidof crystal-dock &>/dev/null; then
    killall crystal-dock 2>/dev/null
    sleep 0.3
    crystal-dock &>/dev/null &
    disown
    pass "crystal-dock restarted"
  fi

  echo "$name" > "$CURRENT_FILE"
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
    ocws_die "No themes found"
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
    [[ -n "${2:-}" ]] || ocws_die "Usage: theme preview <name>"
    bash "$SCRIPT_DIR/theme-engine.sh" preview "$THEMES_DIR/${2}.ini"
    ;;
  *)
    apply_theme "$1"
    ;;
esac
