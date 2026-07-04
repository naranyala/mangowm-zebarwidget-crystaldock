#!/bin/bash
#
# keybind-presets.sh — Switch between keybinding layouts
#
# Presets are full rc.xml files in dotfiles/labwc/presets/.
# Current config is backed up before applying.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PRESET_DIR="$PROJECT_DIR/dotfiles/labwc/presets"
CONFIG_DIR="${HOME}/.config/labwc"
RC_XML="$CONFIG_DIR/rc.xml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
info()  { echo -e "  ${CYAN}→${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }

ACTION="${1:-list}"

case "$ACTION" in
  list|ls)
    echo ""
    echo "== Keybinding Presets =="
    echo ""
    for f in "$PRESET_DIR"/*.xml; do
      name=$(basename "$f" .xml)
      desc=$(grep -oP '<!--\s*\K[^➔]+?(?=\s*-->|$)' "$f" 2>/dev/null | head -1 || echo "")
      active=""
      if [ -f "$RC_XML" ] && cmp -s "$f" "$RC_XML" 2>/dev/null; then
        active=" ${GREEN}(active)${NC}"
      fi
      echo -e "  ${CYAN}${name}${NC}${active:-}"
      [ -n "$desc" ] && echo -e "    ${DIM}${desc}${NC}"
      # Show key modifier summary
      alt_binds=$(grep -c 'key="A-' "$f" 2>/dev/null || true)
      sup_binds=$(grep -c 'key="S-' "$f" 2>/dev/null || true)
      echo -e "    ${DIM}Alt:${NC} $alt_binds  ${DIM}Super:${NC} $sup_binds"
      echo ""
    done
    ;;

  apply)
    PRESET_NAME="${2:-}"
    if [ -z "$PRESET_NAME" ]; then
      fail "Usage: $0 apply <preset-name>"
    fi

    PRESET_FILE="$PRESET_DIR/${PRESET_NAME}.xml"
    if [ ! -f "$PRESET_FILE" ]; then
      fail "Preset not found: $PRESET_NAME"
    fi

    # Validate preset — reject if Client context has Left Press
    CLIENT_CTX=$(sed -n '/<context name="Client">/,/<\/context>/p' "$PRESET_FILE")
    if echo "$CLIENT_CTX" | grep -q 'button="Left" action="Press"'; then
      fail "Preset '$PRESET_NAME' has broken Client context (Left Press). Fix $PRESET_FILE first."
    fi

    # Backup current
    if [ -f "$RC_XML" ]; then
      cp "$RC_XML" "${RC_XML}.preset-backup"
      pass "Backup saved: ${RC_XML}.preset-backup"
    fi

    mkdir -p "$CONFIG_DIR"
    cp "$PRESET_FILE" "$RC_XML"
    pass "Applied preset: $PRESET_NAME"

    if pgrep -x labwc &>/dev/null; then
      labwc --reconfigure 2>/dev/null && pass "labwc reloaded" || warn "Reload failed"
    fi
    ;;

  current)
    if [ ! -f "$RC_XML" ]; then
      fail "No rc.xml found at $RC_XML"
    fi

    echo ""
    echo "== Current Keybindings =="
    echo ""
    for f in "$PRESET_DIR"/*.xml; do
      name=$(basename "$f" .xml)
      if cmp -s "$f" "$RC_XML" 2>/dev/null; then
        pass "Active preset: $name"
        found=true
        break
      fi
    done
    if [ -z "${found:-}" ]; then
      info "Current config doesn't match any preset (customized)"
    fi

    echo ""
    echo "Modifier breakdown:"
    alt_binds=$(grep -c 'key="A-' "$RC_XML" 2>/dev/null || true)
    sup_binds=$(grep -c 'key="S-' "$RC_XML" 2>/dev/null || true)
    echo "  Alt binds:   $alt_binds"
    echo "  Super binds: $sup_binds"
    echo ""

    grep -oP 'key="[^"]+' "$RC_XML" | sed 's/key="//' | sort | while read -r key; do
      action=$(grep -A1 "key=\"$key\"" "$RC_XML" | grep -oP 'name="[^"]+' | head -1 | sed 's/name="//' || echo "")
      fmt=$(echo "$key" | sed 's/A-/Alt+/g; s/S-/Super+/g; s/C-/Ctrl+/g')
      echo -e "  ${CYAN}$fmt${NC} → $action"
    done
    ;;

  diff)
    PRESET_NAME="${2:-}"
    if [ -z "$PRESET_NAME" ]; then
      fail "Usage: $0 diff <preset-name>"
    fi

    PRESET_FILE="$PRESET_DIR/${PRESET_NAME}.xml"
    if [ ! -f "$PRESET_FILE" ]; then
      fail "Preset not found: $PRESET_NAME"
    fi
    if [ ! -f "$RC_XML" ]; then
      fail "No rc.xml at $RC_XML"
    fi

    echo ""
    echo "== Diff: current vs $PRESET_NAME =="
    echo ""
    diff --color=always -u "$RC_XML" "$PRESET_FILE" 2>/dev/null | tail -n +3 || diff -u "$RC_XML" "$PRESET_FILE" | tail -n +3
    ;;

  create)
    PRESET_NAME="${2:-}"
    if [ -z "$PRESET_NAME" ]; then
      fail "Usage: $0 create <preset-name>"
    fi
    if [ ! -f "$RC_XML" ]; then
      fail "No rc.xml at $RC_XML to base preset on"
    fi

    PRESET_FILE="$PRESET_DIR/${PRESET_NAME}.xml"
    if [ -f "$PRESET_FILE" ]; then
      fail "Preset already exists: $PRESET_NAME"
    fi

    cp "$RC_XML" "$PRESET_FILE"
    pass "Created preset '$PRESET_NAME' from current rc.xml"
    info "Edit: $PRESET_FILE"
    ;;

  help|--help|-h|*)
    echo ""
    echo "== Keybinding Presets =="
    echo ""
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  list               List available presets"
    echo "  apply <name>       Apply a preset (backups current)"
    echo "  current            Show current keybinding layout"
    echo "  diff <name>        Diff current vs a preset"
    echo "  create <name>      Save current setup as a new preset"
    echo ""
    echo "Presets are stored in: $PRESET_DIR"
    echo ""
    ;;
esac
