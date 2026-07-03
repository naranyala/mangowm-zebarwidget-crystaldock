#!/bin/bash
#
# font-scale — Global system font scaling (reactive)
#
# Adjusts font size across ALL config surfaces simultaneously:
#   • gsettings/dconf   (GNOME apps pick up changes instantly)
#   • GTK3 settings.ini
#   • GTK4 settings.ini
#   • labwc rc.xml       (window title fonts)
#   • labwc themerc-override
#   • sfwbar config      (panel fonts)
#   • qt6ct config       (Qt apps)
#
# Usage:
#   font-scale up   [step]    Increase font size (default: 0.5)
#   font-scale down [step]    Decrease font size (default: 0.5)
#   font-scale +N             Shortcut: increase by N (e.g. +1, +0.5)
#   font-scale -N             Shortcut: decrease by N (e.g. -1, -0.5)
#   font-scale set  <size>    Set exact font size (6–24)
#   font-scale status         Show current font sizes everywhere
#   font-scale reset          Reset to default (10)
#   font-scale reload         Reload labwc/sfwbar without changing size
#
# Supports 0.5 increments. Min: 6, Max: 24.
#

set -euo pipefail

# --- Config paths ---
GTK3_INI="$HOME/.config/gtk-3.0/settings.ini"
GTK4_INI="$HOME/.config/gtk-4.0/settings.ini"
LABWC_RC="$HOME/.config/labwc/rc.xml"
LABWC_THEMERC="$HOME/.config/labwc/themerc-override"
SFWBAR_CFG="$HOME/.config/sfwbar/sfwbar.config"
QTCT_CONF="$HOME/.config/qt6ct/qt6ct.conf"

# Dotfiles source (for syncing back)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || echo "")"
DOT_GTK3="$PROJECT_DIR/dotfiles/gtk/gtk3-settings.ini"
DOT_GTK4="$PROJECT_DIR/dotfiles/gtk/gtk4-settings.ini"
DOT_RC="$PROJECT_DIR/dotfiles/labwc/rc.xml"
DOT_THEMERC="$PROJECT_DIR/dotfiles/labwc/themerc-override"
DOT_SFWBAR="$PROJECT_DIR/dotfiles/sfwbar/sfwbar.config"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

DEFAULT_SIZE=10
DEFAULT_STEP=0.5
MIN_SIZE=6
MAX_SIZE=24

# ============================================================
# Helpers
# ============================================================

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }

# Format size: strip trailing .0 for whole numbers (10.0 → 10, 9.5 → 9.5)
fmt_size() {
  echo "$1" | awk '{
    if ($1 == int($1)) printf "%d", $1
    else printf "%.1f", $1
  }'
}

# Get current font size from gsettings (primary source of truth)
get_current_size() {
  local font_str
  if command -v gsettings &>/dev/null; then
    font_str=$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null | tr -d "'")
    echo "$font_str" | grep -oE '[0-9]+\.?[0-9]*$' || echo "$DEFAULT_SIZE"
  elif [[ -f "$GTK3_INI" ]]; then
    grep -m1 '^gtk-font-name=' "$GTK3_INI" 2>/dev/null | grep -oE '[0-9]+\.?[0-9]*$' || echo "$DEFAULT_SIZE"
  else
    echo "$DEFAULT_SIZE"
  fi
}

# Get current font family from gsettings
get_current_family() {
  local font_str
  if command -v gsettings &>/dev/null; then
    font_str=$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null | tr -d "'")
    echo "$font_str" | sed -E 's/ +[0-9]+\.?[0-9]*$//' | sed 's/[[:space:]]*$//'
  elif [[ -f "$GTK3_INI" ]]; then
    grep -m1 '^gtk-font-name=' "$GTK3_INI" 2>/dev/null | \
      sed 's/^gtk-font-name=//' | sed -E 's/,? *[0-9]+\.?[0-9]*$//' | sed 's/[[:space:]]*$//'
  else
    echo "Noto Sans"
  fi
}

# Clamp size within bounds
clamp_size() {
  echo "$1" | awk -v min="$MIN_SIZE" -v max="$MAX_SIZE" '{
    if ($1 < min) print min
    else if ($1 > max) print max
    else printf "%.1f", $1
  }'
}

# Parse +/- syntax: +1 → current+1, -0.5 → current-0.5, 12 → 12
parse_modifier() {
  local current="$1" input="$2"
  if [[ "$input" =~ ^[+-] ]]; then
    echo "$current $input" | awk '{printf "%.1f", $1 + $2}'
  elif [[ "$input" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    echo "$input"
  else
    fail "Invalid size: '$input'. Use +1, -0.5, up, down, or absolute like 12"
    exit 1
  fi
}

# ============================================================
# Updaters — each updates one config surface
# ============================================================

update_gsettings() {
  local size="$1" family="$2" fsize
  fsize=$(fmt_size "$size")

  if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.interface font-name "$family $fsize" 2>/dev/null && \
      pass "gsettings font-name: $family $fsize" || \
      fail "gsettings font-name"

    # Document font
    local doc_font doc_family doc_size new_doc_size
    doc_font=$(gsettings get org.gnome.desktop.interface document-font-name 2>/dev/null | tr -d "'")
    if [[ -n "$doc_font" ]]; then
      doc_family=$(echo "$doc_font" | sed -E 's/ +[0-9]+\.?[0-9]*$//' | sed 's/[[:space:]]*$//')
      new_doc_size=$(fmt_size "$size")
      gsettings set org.gnome.desktop.interface document-font-name "$doc_family $new_doc_size" 2>/dev/null && \
        pass "gsettings document-font: $doc_family $new_doc_size" || true
    fi

    # Titlebar font
    local tb_font tb_family
    tb_font=$(gsettings get org.gnome.desktop.wm.preferences titlebar-font 2>/dev/null | tr -d "'" || true)
    if [[ -n "$tb_font" ]]; then
      tb_family=$(echo "$tb_font" | sed -E 's/ +[0-9]+\.?[0-9]*$//' | sed 's/[[:space:]]*$//')
      gsettings set org.gnome.desktop.wm.preferences titlebar-font "$tb_family $fsize" 2>/dev/null && \
        pass "gsettings titlebar-font: $tb_family $fsize" || true
    fi

    # Monospace
    gsettings set org.gnome.desktop.interface monospace-font-name "Noto Sans Mono $fsize" 2>/dev/null && \
      pass "gsettings monospace-font: Noto Sans Mono $fsize" || true
  else
    warn "gsettings not available"
  fi
}

update_gtk_ini() {
  local ini_file="$1" size="$2" label="$3"
  local fsize family

  if [[ ! -f "$ini_file" ]]; then
    warn "$label: file not found"
    return
  fi

  fsize=$(fmt_size "$size")
  family=$(grep -m1 '^gtk-font-name=' "$ini_file" 2>/dev/null | \
    sed 's/^gtk-font-name=//' | sed -E 's/,? *[0-9]+\.?[0-9]*$//' | sed 's/[[:space:]]*$//')
  [[ -z "$family" ]] && family="Noto Sans"

  sed -i "s/^gtk-font-name=.*/gtk-font-name=$family, $fsize/" "$ini_file"
  sed -i "s/^gtk-monospace-font-name=.*/gtk-monospace-font-name=Noto Sans Mono, $fsize/" "$ini_file"
  pass "$label: $family, $fsize"
}

update_labwc_rc() {
  local rc_file="$1" size="$2"
  local fsize

  if [[ ! -f "$rc_file" ]]; then
    warn "labwc rc.xml: not found"
    return
  fi

  fsize=$(fmt_size "$size")
  sed -i -E "/<theme>/,/<\/theme>/s|<size>[0-9]+\.?[0-9]*</size>|<size>$fsize</size>|g" "$rc_file"
  pass "labwc rc.xml fonts: $fsize"
}

update_labwc_themerc() {
  local themerc="$1" size="$2"
  local fsize

  if [[ ! -f "$themerc" ]]; then
    warn "labwc themerc-override: not found"
    return
  fi

  fsize=$(fmt_size "$size")
  sed -i -E "s/(activetextfont=.*) [0-9]+\.?[0-9]*/\1 $fsize/" "$themerc"
  sed -i -E "s/(inactivetextfont=.*) [0-9]+\.?[0-9]*/\1 $fsize/" "$themerc"
  pass "labwc themerc: $fsize"
}

update_sfwbar() {
  local cfg="$1" size="$2"
  local px_size pager_px

  if [[ ! -f "$cfg" ]]; then
    warn "sfwbar config: not found"
    return
  fi

  px_size=$(echo "$size" | awk '{printf "%d", $1 * 1.2}')
  pager_px=$(echo "$px_size" | awk '{v = $1 - 1; if (v < 8) v = 8; printf "%d", v}')

  sed -i -E "/^label \{/,/^\}/{s/font-size: [0-9]+\.?[0-9]*px;/font-size: ${px_size}px;/}" "$cfg"
  sed -i -E "/button#pager_item label/,/^\}/{s/font-size: [0-9]+\.?[0-9]*px;/font-size: ${pager_px}px;/}" "$cfg"
  pass "sfwbar: ${px_size}px (pager: ${pager_px}px)"
}

update_qt6ct() {
  local size="$1" fsize mono_size
  fsize=$(fmt_size "$size")
  mono_size=$(echo "$size" | awk '{printf "%d", $1}')

  if [[ -f "$QTCT_CONF" ]]; then
    sed -i "s/^font=.*/font=Noto Sans,$fsize,-1,5,50,0,0,0,0,0/" "$QTCT_CONF"
    sed -i "s/^monoFont=.*/monoFont=Noto Sans Mono,$mono_size,-1,5,50,0,0,0,0,0/" "$QTCT_CONF"
    pass "qt6ct: Noto Sans $fsize"
  else
    warn "qt6ct config not found, skipped"
  fi
}

# ============================================================
# Sync dotfiles source (optional, if project dir exists)
# ============================================================

sync_dotfiles() {
  local size="$1"

  if [[ -z "$PROJECT_DIR" || ! -d "$PROJECT_DIR/dotfiles" ]]; then
    return
  fi

  echo ""
  echo -e "${DIM}  Syncing dotfiles source...${NC}"

  [[ -f "$DOT_GTK3" ]] && update_gtk_ini "$DOT_GTK3" "$size" "dotfiles/gtk3"
  [[ -f "$DOT_GTK4" ]] && update_gtk_ini "$DOT_GTK4" "$size" "dotfiles/gtk4"
  [[ -f "$DOT_RC" ]] && update_labwc_rc "$DOT_RC" "$size"
  [[ -f "$DOT_THEMERC" ]] && update_labwc_themerc "$DOT_THEMERC" "$size"
  [[ -f "$DOT_SFWBAR" ]] && update_sfwbar "$DOT_SFWBAR" "$size"
}

# ============================================================
# Live reload — trigger compositors to pick up changes
# ============================================================

live_reload() {
  echo ""
  info "Triggering live reload..."

  # labwc reconfigure (SIGHUP)
  if pidof labwc &>/dev/null; then
    kill -SIGHUP "$(pidof labwc)" 2>/dev/null && \
      pass "labwc: reconfigured" || warn "labwc: reconfigure failed"
  fi

  # sfwbar restart (no hot-reload)
  if pidof sfwbar &>/dev/null; then
    killall sfwbar 2>/dev/null
    sleep 0.3
    sfwbar &>/dev/null &
    disown
    pass "sfwbar: restarted"
  fi

  # GTK apps pick up gsettings changes instantly
  pass "gsettings: changes propagated to running apps"
}

# ============================================================
# Commands
# ============================================================

cmd_status() {
  echo -e "${BOLD}Font Scale — Current Status${NC}"
  echo ""

  local size family
  size=$(get_current_size)
  family=$(get_current_family)

  echo -e "  ${BOLD}Primary font:${NC} $family $(fmt_size "$size")"
  echo ""

  if command -v gsettings &>/dev/null; then
    echo -e "  ${CYAN}gsettings:${NC}"
    echo "    font-name:          $(gsettings get org.gnome.desktop.interface font-name 2>/dev/null | tr -d "'")"
    echo "    document-font-name: $(gsettings get org.gnome.desktop.interface document-font-name 2>/dev/null | tr -d "'")"
    echo "    monospace-font:     $(gsettings get org.gnome.desktop.interface monospace-font-name 2>/dev/null | tr -d "'")"
    echo "    titlebar-font:      $(gsettings get org.gnome.desktop.wm.preferences titlebar-font 2>/dev/null | tr -d "'")"
  fi

  echo ""
  echo -e "  ${CYAN}GTK3 settings.ini:${NC}"
  if [[ -f "$GTK3_INI" ]]; then
    echo "    $(grep '^gtk-font-name=' "$GTK3_INI" 2>/dev/null || echo 'not set')"
  else
    echo "    (not found)"
  fi

  echo -e "  ${CYAN}GTK4 settings.ini:${NC}"
  if [[ -f "$GTK4_INI" ]]; then
    echo "    $(grep '^gtk-font-name=' "$GTK4_INI" 2>/dev/null || echo 'not set')"
  else
    echo "    (not found)"
  fi

  echo ""
  echo -e "  ${CYAN}labwc rc.xml:${NC}"
  if [[ -f "$LABWC_RC" ]]; then
    local rc_size
    rc_size=$(sed -n '/<theme>/,/<\/theme>/p' "$LABWC_RC" | grep -oP '<size>\K[^<]+' | head -1)
    echo "    theme font size: ${rc_size:-not set}"
  else
    echo "    (not found)"
  fi

  echo -e "  ${CYAN}labwc themerc-override:${NC}"
  if [[ -f "$LABWC_THEMERC" ]]; then
    echo "    $(grep 'activetextfont=' "$LABWC_THEMERC" 2>/dev/null | head -1 || echo 'not set')"
  else
    echo "    (not found)"
  fi

  echo ""
  echo -e "  ${CYAN}sfwbar:${NC}"
  if [[ -f "$SFWBAR_CFG" ]]; then
    local sfwbar_size
    sfwbar_size=$(sed -n '/^label {/,/^}/p' "$SFWBAR_CFG" | grep -oP 'font-size:\s*\K[0-9.]+' | head -1)
    echo "    label font-size: ${sfwbar_size:-not set}px"
  else
    echo "    (not found)"
  fi

  echo ""
  echo -e "  ${CYAN}qt6ct:${NC}"
  if [[ -f "$QTCT_CONF" ]]; then
    grep -E '^(font|monoFont)=' "$QTCT_CONF" 2>/dev/null | sed 's/^/    /' || echo "    (not set)"
  else
    echo "    (not found)"
  fi

  echo ""
  echo -e "  ${DIM}Range: ${MIN_SIZE}–${MAX_SIZE} | Step: ${DEFAULT_STEP}${NC}"
}

cmd_apply() {
  local new_size="$1"
  local family
  family=$(get_current_family)
  [[ -z "$family" ]] && family="Noto Sans"

  local fsize
  fsize=$(fmt_size "$new_size")

  echo -e "${BOLD}Font Scale → $fsize${NC}"
  echo ""

  update_gsettings "$new_size" "$family"
  update_gtk_ini "$GTK3_INI" "$new_size" "GTK3 settings.ini"
  update_gtk_ini "$GTK4_INI" "$new_size" "GTK4 settings.ini"
  update_labwc_rc "$LABWC_RC" "$new_size"
  update_labwc_themerc "$LABWC_THEMERC" "$new_size"
  update_sfwbar "$SFWBAR_CFG" "$new_size"
  update_qt6ct "$new_size"

  sync_dotfiles "$new_size"
  live_reload

  echo ""
  echo -e "  ${GREEN}${BOLD}Done!${NC} Font size: ${BOLD}$fsize${NC}"
}

cmd_up() {
  local step="${1:-$DEFAULT_STEP}"
  local current new_raw new_clamped
  current=$(get_current_size)
  new_raw=$(echo "$current $step" | awk '{printf "%.1f", $1 + $2}')
  new_clamped=$(clamp_size "$new_raw")

  if [[ "$new_clamped" == "$current" ]]; then
    warn "Already at maximum size ($MAX_SIZE)"
    return 1
  fi

  cmd_apply "$new_clamped"
}

cmd_down() {
  local step="${1:-$DEFAULT_STEP}"
  local current new_raw new_clamped
  current=$(get_current_size)
  new_raw=$(echo "$current $step" | awk '{printf "%.1f", $1 - $2}')
  new_clamped=$(clamp_size "$new_raw")

  if [[ "$new_clamped" == "$current" ]]; then
    warn "Already at minimum size ($MIN_SIZE)"
    return 1
  fi

  cmd_apply "$new_clamped"
}

cmd_set() {
  local size="$1"

  if [[ -z "$size" ]]; then
    fail "Usage: font-scale set <size>"
    exit 1
  fi

  if ! echo "$size" | grep -qE '^[0-9]+\.?[0-9]*$'; then
    fail "Invalid size: $size (must be a number)"
    exit 1
  fi

  local clamped
  clamped=$(clamp_size "$size")
  cmd_apply "$clamped"
}

cmd_reset() {
  echo -e "${BOLD}Resetting to default font size ($DEFAULT_SIZE)${NC}"
  cmd_apply "$DEFAULT_SIZE"
}

cmd_reload() {
  live_reload
}

# ============================================================
# Main
# ============================================================

usage() {
  echo -e "${BOLD}font-scale${NC} — Global system font scaling"
  echo ""
  echo "Usage:"
  echo "  font-scale up   [step]    Increase font size (default: $DEFAULT_STEP)"
  echo "  font-scale down [step]    Decrease font size (default: $DEFAULT_STEP)"
  echo "  font-scale +N             Shortcut: increase by N"
  echo "  font-scale -N             Shortcut: decrease by N"
  echo "  font-scale set  <size>    Set exact font size (range: $MIN_SIZE–$MAX_SIZE)"
  echo "  font-scale status         Show current font sizes"
  echo "  font-scale reset          Reset to default ($DEFAULT_SIZE)"
  echo "  font-scale reload         Reload labwc/sfwbar without changing size"
  echo ""
  echo "Examples:"
  echo "  font-scale down           # 10 → 9.5"
  echo "  font-scale down 1         # 10 → 9"
  echo "  font-scale +0.5           # 10 → 10.5"
  echo "  font-scale -1             # 10 → 9"
  echo "  font-scale set 11         # Set all fonts to 11"
  echo "  font-scale status         # Show all font sizes"
  echo ""
  echo "Changes are applied reactively — running apps update immediately."
}

case "${1:-}" in
  up)      cmd_up "${2:-}" ;;
  down)    cmd_down "${2:-}" ;;
  set)     cmd_set "${2:-}" ;;
  status)  cmd_status ;;
  reset)   cmd_reset ;;
  reload)  cmd_reload ;;
  +[0-9]*) cmd_up "${1#+}" ;;
  -[0-9]*) cmd_down "${1#-}" ;;
  -h|--help|help) usage ;;
  [0-9]*)  cmd_set "$1" ;;
  *)
    usage
    exit 1
    ;;
esac
