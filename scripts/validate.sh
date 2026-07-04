#!/bin/bash
#
# validate.sh — Comprehensive validation of labwc + sfwbar + crystal-dock setup
#
# Checks: binaries, configs, permissions, dependencies, autostart, themes
# Exit code = number of errors found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="${HOME}/.config/labwc"
SFWBAR_DIR="${HOME}/.config/sfwbar"

ERRORS=0
WARNINGS=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}✓${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; ERRORS=$((ERRORS + 1)); }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; WARNINGS=$((WARNINGS + 1)); }
info()  { echo -e "  ${CYAN}→${NC} $1"; }
section() { echo -e "\n${BOLD}[$1]${NC}"; }

# ============================================================
section "1. Binaries"
# ============================================================
REQUIRED_BINS=(labwc sfwbar swaybg)
OPTIONAL_BINS=(crystal-dock foot rofi grim slurp wl-copy playerctl wpctl gammastep redshift mako dunst libinput gsettings)

for bin in "${REQUIRED_BINS[@]}"; do
  if command -v "$bin" &>/dev/null; then
    pass "$bin: $(command -v "$bin")"
  else
    fail "$bin: NOT FOUND (required)"
  fi
done

for bin in "${OPTIONAL_BINS[@]}"; do
  if command -v "$bin" &>/dev/null; then
    pass "$bin: $(command -v "$bin")"
  else
    warn "$bin: not found (optional)"
  fi
done

# ============================================================
section "2. labwc Configuration"
# ============================================================
if [ -d "$CONFIG_DIR" ]; then
  pass "Config directory exists: $CONFIG_DIR"
else
  fail "Config directory missing: $CONFIG_DIR"
fi

for cfg in rc.xml autostart environment menu.xml themerc-override; do
  if [ -f "$CONFIG_DIR/$cfg" ]; then
    if [ -r "$CONFIG_DIR/$cfg" ]; then
      pass "$cfg: exists and readable"
    else
      fail "$cfg: exists but NOT readable"
    fi
  else
    fail "$cfg: MISSING"
  fi
done

# Check autostart is executable
if [ -f "$CONFIG_DIR/autostart" ]; then
  if [ -x "$CONFIG_DIR/autostart" ]; then
    pass "autostart: executable"
  else
    warn "autostart: NOT executable (fix: chmod +x $CONFIG_DIR/autostart)"
  fi
fi

# Validate rc.xml syntax
if command -v xmllint &>/dev/null && [ -f "$CONFIG_DIR/rc.xml" ]; then
  if xmllint --noout "$CONFIG_DIR/rc.xml" 2>/dev/null; then
    pass "rc.xml: valid XML"
  else
    fail "rc.xml: INVALID XML"
  fi
fi

# Check for broken Client mouse context (Left Press consumes clicks)
if [ -f "$CONFIG_DIR/rc.xml" ]; then
  CLIENT_CTX=$(sed -n '/<context name="Client">/,/<\/context>/p' "$CONFIG_DIR/rc.xml")
  if echo "$CLIENT_CTX" | grep -q 'button="Left" action="Press"'; then
    fail "rc.xml: Client context has 'Left Press' binding — breaks click forwarding to apps"
  else
    pass "rc.xml: Client mouse context OK (no Left Press)"
  fi
fi

# Check for unescaped & in XML (causes parse errors)
if [ -f "$CONFIG_DIR/rc.xml" ]; then
  UNESCAPED=$(grep -n '&&' "$CONFIG_DIR/rc.xml" 2>/dev/null | grep -v '&amp;' | head -1 || true)
  if [ -n "$UNESCAPED" ]; then
    fail "rc.xml: unescaped '&' at $(echo "$UNESCAPED" | cut -d: -f1) — use &amp; in XML"
  else
    pass "rc.xml: XML entities OK"
  fi
fi

# Check for hardware cursor fix (wlroots click bugs)
if [ -f "$CONFIG_DIR/environment" ]; then
  if grep -q "^WLR_NO_HARDWARE_CURSORS=1" "$CONFIG_DIR/environment"; then
    pass "environment: software cursors enabled (fixes click bugs)"
  else
    warn "environment: WLR_NO_HARDWARE_CURSORS=1 missing (can cause click alignment bugs)"
  fi
fi

# Check for crystal-dock in autostart
if [ -f "$CONFIG_DIR/autostart" ]; then
  if grep -q "crystal-dock" "$CONFIG_DIR/autostart"; then
    pass "autostart: crystal-dock configured"
  else
    warn "autostart: crystal-dock NOT in autostart"
  fi
  if grep -q "sfwbar" "$CONFIG_DIR/autostart"; then
    pass "autostart: sfwbar configured"
  else
    warn "autostart: sfwbar NOT in autostart"
  fi
  if grep -q "gammastep\|redshift" "$CONFIG_DIR/autostart"; then
    pass "autostart: screen protection configured"
  else
    warn "autostart: no screen protection (gammastep/redshift)"
  fi
fi

# ============================================================
section "3. SFWBar Configuration"
# ============================================================
SFWBAR_DIR="${HOME}/.config/sfwbar"
if [ -d "$SFWBAR_DIR" ]; then
  pass "SFWBar config directory: $SFWBAR_DIR"
else
  warn "SFWBar config directory missing: $SFWBAR_DIR"
fi

if [ -f "$SFWBAR_DIR/sfwbar.config" ]; then
  pass "sfwbar.config exists"
else
  warn "sfwbar.config missing"
fi

if command -v sfwbar &>/dev/null; then
  pass "sfwbar binary: $(command -v sfwbar)"
else
  warn "sfwbar not installed"
fi

# Check for widget files
WIDGET_COUNT=0
for widget_file in "$SFWBAR_DIR"/*.widget; do
  if [ -f "$widget_file" ]; then
    widget_name=$(basename "$widget_file" .widget)
    pass "Widget '$widget_name': installed"
    ((WIDGET_COUNT++))
  fi
done 2>/dev/null
info "Total widget files found: $WIDGET_COUNT"

# ============================================================
section "4. Wallpaper"
# ============================================================
if [ -f "$HOME/.local/bin/wallpaper" ]; then
  pass "Wallpaper script installed"
  if [ -x "$HOME/.local/bin/wallpaper" ]; then
    pass "Wallpaper script: executable"
  else
    warn "Wallpaper script: NOT executable"
  fi
else
  warn "Wallpaper script not installed"
fi

if [ -d "$HOME/Pictures/wallpapers" ]; then
  WP_COUNT=$(find "$HOME/Pictures/wallpapers" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) 2>/dev/null | wc -l)
  if [ "$WP_COUNT" -gt 0 ]; then
    pass "Wallpapers found: $WP_COUNT files"
  else
    warn "Wallpaper directory exists but no images found"
  fi
else
  warn "Wallpaper directory not found: ~/Pictures/wallpapers"
fi

# ============================================================
section "5. Dependencies"
# ============================================================
MISSING_LIBS=()
for lib in wayland-client wlroots libxml-2.0 cairo pangocairo glib-2.0 xkbcommon; do
  if pkg-config --exists "$lib" 2>/dev/null; then
    pass "Library: $lib"
  else
    warn "Library: $lib (dev package may be needed)"
  fi
done

# ============================================================
section "6. Display Server"
# ============================================================
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
  pass "Wayland session active: $WAYLAND_DISPLAY"
else
  info "No Wayland session detected (running from TTY or X11)"
fi

if [ -n "${XDG_SESSION_TYPE:-}" ]; then
  pass "Session type: $XDG_SESSION_TYPE"
else
  warn "XDG_SESSION_TYPE not set"
fi

# ============================================================
section "7. User Environment"
# ============================================================
for var in XDG_CONFIG_HOME XDG_DATA_HOME XDG_RUNTIME_DIR; do
  val="${!var:-}"
  if [ -n "$val" ]; then
    pass "$var=$val"
  else
    info "$var: not set (will use default)"
  fi
done

# Check PATH includes ~/.local/bin
if echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
  pass "~/.local/bin is in PATH"
else
  warn "~/.local/bin NOT in PATH"
fi

# ============================================================
section "8. Permissions"
# ============================================================
for dir in "$CONFIG_DIR" "$SFWBAR_DIR" "$HOME/.local/bin"; do
  if [ -d "$dir" ]; then
    PERMS=$(stat -c "%a" "$dir" 2>/dev/null || stat -f "%Lp" "$dir" 2>/dev/null || echo "???")
    if [ "$PERMS" = "700" ] || [ "$PERMS" = "755" ] || [ "$PERMS" = "775" ]; then
      pass "$(basename "$dir"): permissions OK ($PERMS)"
    else
      warn "$(basename "$dir"): unusual permissions ($PERMS)"
    fi
  fi
done

# ============================================================
section "Summary"
# ============================================================
echo ""
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All checks passed!${NC}"
elif [ "$ERRORS" -eq 0 ]; then
  echo -e "${YELLOW}${BOLD}$WARNINGS warning(s)${NC} — setup is functional but could be improved"
else
  echo -e "${RED}${BOLD}$ERRORS error(s), $WARNINGS warning(s)${NC}"
fi
echo ""

exit "$ERRORS"
