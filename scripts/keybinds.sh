#!/bin/bash
#
# keybinds.sh — View and manage labwc keybindings
#
# List, add, remove, and validate keybindings from rc.xml.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${HOME}/.config/labwc"
RC_XML="$CONFIG_DIR/rc.xml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
info()  { echo -e "  ${CYAN}→${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
section() { echo -e "\n${BOLD}[$1]${NC}"; }

ACTION="${1:-list}"
shift || true

# ============================================================
# Parse rc.xml keybindings
# ============================================================
parse_keybindings() {
  if [ ! -f "$RC_XML" ]; then
    fail "rc.xml not found: $RC_XML"
  fi
  
  # Extract keybinds with actions
  grep -oP '<keybind key="([^"]+)".*?</keybind>' "$RC_XML" 2>/dev/null | \
  sed 's/<keybind key="//' | sed 's/".*//' | \
  while read -r key; do
    # Get the action for this key
    action=$(grep -A5 "key=\"$key\"" "$RC_XML" 2>/dev/null | \
             grep -oP 'name="([^"]+)"' | head -1 | \
             sed 's/name="//' | sed 's/"//')
    echo "$key|$action"
  done
}

# ============================================================
case "$ACTION" in
# ============================================================

  list|ls)
    echo ""
    echo "== labwc Keybindings =="
    echo ""
    
    if [ ! -f "$RC_XML" ]; then
      fail "rc.xml not found: $RC_XML"
    fi
    
    # Parse and display
    parse_keybindings | while IFS='|' read -r key action; do
      # Format key for display
      display_key=$(echo "$key" | sed 's/A-/Alt+/g' | sed 's/S-/Super+/g' | sed 's/C-/Ctrl+/g')
      echo -e "  ${CYAN}${display_key}${NC} → ${action}"
    done
    echo ""
    ;;

  search|grep)
    PATTERN="${1:-}"
    if [ -z "$PATTERN" ]; then
      fail "Usage: $0 search <pattern>"
    fi
    
    echo ""
    echo "== Keybindings matching: $PATTERN =="
    echo ""
    
    parse_keybindings | grep -i "$PATTERN" | while IFS='|' read -r key action; do
      display_key=$(echo "$key" | sed 's/A-/Alt+/g' | sed 's/S-/Super+/g' | sed 's/C-/Ctrl+/g')
      echo -e "  ${CYAN}${display_key}${NC} → ${action}"
    done
    echo ""
    ;;

  check)
    echo ""
    echo "== Checking Keybinding Conflicts =="
    echo ""
    
    parse_keybindings | sort | uniq -d | while IFS='|' read -r key action; do
      warn "Duplicate key: $key"
    done
    
    # Check for common conflicts
    CONFLICTS=()
    while IFS='|' read -r key action; do
      case "$key" in
        A-F4) CONFLICTS+=("$key: $action (may conflict with window close)") ;;
        S-q) CONFLICTS+=("$key: $action (may conflict with quick actions)") ;;
      esac
    done < <(parse_keybindings)
    
    if [ ${#CONFLICTS[@]} -gt 0 ]; then
      echo ""
      warn "Potential conflicts:"
      for c in "${CONFLICTS[@]}"; do
        echo "    $c"
      done
    else
      pass "No conflicts detected"
    fi
    echo ""
    ;;

  add)
    KEY="${1:-}"
    ACTION_NAME="${2:-}"
    COMMAND="${3:-}"
    
    if [ -z "$KEY" ] || [ -z "$ACTION_NAME" ]; then
      fail "Usage: $0 add <key> <action> [command]"
      echo ""
      echo "Actions: Execute, Close, Exit, Reload, ToggleFloating, ToggleFullscreen,"
      echo "         ToggleMaximize, Focus, Swap, GoToDesktop, SendToDesktop, SetGap"
      echo ""
      echo "Examples:"
      echo "  $0 add A-x Execute 'flameshot gui'"
      echo "  $0 add S-Return Execute contour"
      echo "  $0 add A-F4 Close"
      exit 1
    fi
    
    if [ ! -f "$RC_XML" ]; then
      fail "rc.xml not found"
    fi
    
    # Build action XML
    case "$ACTION_NAME" in
      Execute)
        ACTION_XML="<action name=\"Execute\"><command>${COMMAND:-}</command></action>"
        ;;
      Focus|Swap)
        DIRECTION="${COMMAND:-left}"
        ACTION_XML="<action name=\"${ACTION_NAME}\"><direction>${DIRECTION}</direction></action>"
        ;;
      GoToDesktop|SendToDesktop)
        DESKTOP="${COMMAND:-1}"
        ACTION_XML="<action name=\"${ACTION_NAME}\"><to>${DESKTOP}</to></action>"
        ;;
      SetGap)
        AMOUNT="${COMMAND:-+5}"
        ACTION_XML="<action name=\"SetGap\"><amount>${AMOUNT}</amount><side>all</side></action>"
        ;;
      *)
        ACTION_XML="<action name=\"${ACTION_NAME}\"/>"
        ;;
    esac
    
    # Insert before </keyboard>
    KEYBIND="    <keybind key=\"${KEY}\">${ACTION_XML}</keybind>"
    
    # Backup
    cp "$RC_XML" "${RC_XML}.backup"
    
    sed -i "s|</keyboard>|${KEYBIND}\n  </keyboard>|" "$RC_XML"
    
    pass "Added keybinding: $KEY → $ACTION_NAME"
    info "Backup saved: ${RC_XML}.backup"
    echo ""
    ;;

  remove|rm)
    KEY="${1:-}"
    if [ -z "$KEY" ]; then
      fail "Usage: $0 remove <key>"
      echo ""
      echo "Example: $0 remove A-x"
      exit 1
    fi
    
    if [ ! -f "$RC_XML" ]; then
      fail "rc.xml not found"
    fi
    
    # Backup
    cp "$RC_XML" "${RC_XML}.backup"
    
    # Remove keybind
    sed -i "/<keybind key=\"${KEY}\"/,/<\/keybind>/d" "$RC_XML"
    
    pass "Removed keybinding: $KEY"
    info "Backup saved: ${RC_XML}.backup"
    echo ""
    ;;

  validate)
    echo ""
    echo "== Validating Keybindings =="
    echo ""
    
    if ! command -v xmllint &>/dev/null; then
      warn "xmllint not found, skipping XML validation"
    else
      if xmllint --noout "$RC_XML" 2>/dev/null; then
        pass "XML syntax valid"
      else
        fail "XML syntax ERROR"
      fi
    fi
    
    # Check for missing actions
    parse_keybindings | while IFS='|' read -r key action; do
      if [ -z "$action" ]; then
        warn "Key $key has no action"
      fi
    done
    
    pass "Keybinding validation complete"
    echo ""
    ;;

  help|--help|-h|*)
    echo ""
    echo "== Keybind Manager =="
    echo ""
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  list              List all keybindings"
    echo "  search <pattern>  Search keybindings"
    echo "  check             Check for conflicts"
    echo "  add <key> <action> [cmd]  Add a keybinding"
    echo "  remove <key>      Remove a keybinding"
    echo "  validate          Validate rc.xml"
    echo "  help              Show this help"
    echo ""
    echo "Key Format:"
    echo "  A- = Alt, S- = Super, C- = Ctrl"
    echo "  Examples: A-x, S-Return, A-S-1, A-F4"
    echo ""
    echo "Actions:"
    echo "  Execute, Close, Exit, Reload"
    echo "  ToggleFloating, ToggleFullscreen, ToggleMaximize"
    echo "  Focus, Swap, GoToDesktop, SendToDesktop"
    echo "  SetGap, ShowMenu"
    echo ""
    echo "Examples:"
    echo "  $0 add A-x Execute 'flameshot gui'"
    echo "  $0 add S-Return Execute foot"
    echo "  $0 add A-1 GoToDesktop 1"
    echo "  $0 remove A-x"
    echo ""
    ;;
esac
