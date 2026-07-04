#!/bin/bash
#
# fix-labwc-clicks.sh — Comprehensive fix for labwc text selection & click issues
#
# Diagnoses and fixes:
#   1. rc.xml Client context 'Left Press' binding (captures clicks before apps)
#   2. rc.xml Client context 'Right Press' / 'Middle Press' (same issue)
#   3. <default /> mouse tag causing built-in click-consuming bindings
#   4. Missing WLR_NO_HARDWARE_CURSORS=1 (cursor misalignment)
#   5. Missing clipboard daemon (wl-paste / cliphist)
#   6. Unescaped & in rc.xml (XML parse errors)
#   7. Broken autostart permissions
#
# Usage:
#   ./fix-labwc-clicks.sh              # diagnose + fix
#   ./fix-labwc-clicks.sh --check      # diagnose only (no changes)
#   ./fix-labwc-clicks.sh --fix        # force fix without prompts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RC_XML="${HOME}/.config/labwc/rc.xml"
ENV_FILE="${HOME}/.config/labwc/environment"
AUTOSTART="${HOME}/.config/labwc/autostart"
DOTFILES_RC="${PROJECT_DIR}/dotfiles/labwc/rc.xml"

MODE="${1:---check}"
FORCE=0
[[ "$MODE" == "--fix" ]] && FORCE=1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

ISSUES=0
FIXED=0

pass()  { echo -e "  ${GREEN}✓${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; ISSUES=$((ISSUES + 1)); }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; ISSUES=$((ISSUES + 1)); }
fixed() { echo -e "  ${GREEN}→${NC} ${CYAN}FIXED:${NC} $1"; FIXED=$((FIXED + 1)); }
info()  { echo -e "  ${CYAN}→${NC} $1"; }
skip()  { echo -e "  ${DIM}→${NC} $1"; }
section() { echo -e "\n${BOLD}[$1]${NC}"; }

echo ""
echo -e "${BOLD}=====================================================${NC}"
echo -e "${BOLD} Labwc Click & Text Selection Fixer${NC}"
echo -e "${BOLD}=====================================================${NC}"
echo ""
if [[ "$MODE" == "--check" ]]; then
  echo -e "  Mode: ${CYAN}diagnose${NC} (use --fix to apply fixes)"
elif [[ "$MODE" == "--fix" ]]; then
  echo -e "  Mode: ${GREEN}fix${NC} (will modify files)"
fi
echo ""

# ============================================================
section "1. rc.xml — Client Context Mouse Bindings"
# ============================================================

if [[ ! -f "$RC_XML" ]]; then
  fail "rc.xml not found at $RC_XML"
  echo -e "  ${DIM}Run ./dotfiles/install.sh first to install config files${NC}"
  exit 1
fi

# Check XML validity first
if command -v xmllint &>/dev/null; then
  if xmllint --noout "$RC_XML" 2>/dev/null; then
    pass "rc.xml is valid XML"
  else
    fail "rc.xml has INVALID XML — parse errors will prevent labwc from loading mouse config"
  fi
fi

# Check for unescaped & in XML
UNESCAPED=$(grep -n '&&' "$RC_XML" 2>/dev/null | grep -v '&amp;' | grep -v '&lt;\|&gt;\|&quot;\|&apos;' || true)
if [[ -n "$UNESCAPED" ]]; then
  fail "rc.xml has unescaped '&' — causes XML parse errors"
  echo "$UNESCAPED" | while read -r line; do
    echo -e "    ${DIM}$line${NC}"
  done
fi

# Check Client context for click-consuming bindings
echo ""
info "Checking <context name=\"Client\"> for click-consuming bindings..."

# Extract the Client context block
CLIENT_CTX=$(sed -n '/<context name="Client">/,/<\/context>/p' "$RC_XML" 2>/dev/null || true)

if [[ -z "$CLIENT_CTX" ]]; then
  warn "No Client context found in rc.xml — labwc defaults will apply"
  echo -e "    ${DIM}labwc defaults may include Left Press binding that captures clicks${NC}"
else
  # Check for Left Press (breaks text selection + left clicks)
  if echo "$CLIENT_CTX" | grep -q 'button="Left" action="Press"'; then
    fail "Client context has 'Left Press' binding — BREAKS text selection and left clicks"
    if [[ "$MODE" == "--fix" ]] || [[ "$FORCE" -eq 1 ]]; then
      # Use Python for safe XML manipulation
      python3 -c "
import xml.etree.ElementTree as ET
import sys

tree = ET.parse('$RC_XML')
root = tree.getroot()

for mouse in root.findall('mouse'):
    for context in mouse.findall('context'):
        if context.get('name') == 'Client':
            to_remove = []
            for mb in context.findall('mousebind'):
                if mb.get('button') == 'Left' and mb.get('action') == 'Press':
                    to_remove.append(mb)
            for mb in to_remove:
                context.remove(mb)

tree.write('$RC_XML', encoding='UTF-8', xml_declaration=True)
print('done')
" 2>/dev/null && fixed "Removed 'Left Press' binding from Client context" || warn "Could not auto-fix (run manually or check XML syntax)"
    fi
  else
    pass "Client context: no 'Left Press' binding (OK)"
  fi

  # Check for Right Press (can interfere with context menus)
  if echo "$CLIENT_CTX" | grep -q 'button="Right" action="Press"'; then
    warn "Client context has 'Right Press' binding — may interfere with right-click menus"
    if [[ "$MODE" == "--fix" ]] || [[ "$FORCE" -eq 1 ]]; then
      python3 -c "
import xml.etree.ElementTree as ET

tree = ET.parse('$RC_XML')
root = tree.getroot()

for mouse in root.findall('mouse'):
    for context in mouse.findall('context'):
        if context.get('name') == 'Client':
            to_remove = []
            for mb in context.findall('mousebind'):
                if mb.get('button') == 'Right' and mb.get('action') == 'Press':
                    to_remove.append(mb)
            for mb in to_remove:
                context.remove(mb)

tree.write('$RC_XML', encoding='UTF-8', xml_declaration=True)
" 2>/dev/null && fixed "Removed 'Right Press' binding from Client context" || warn "Could not auto-fix"
    fi
  else
    pass "Client context: no 'Right Press' binding (OK)"
  fi

  # Check for Middle Press
  if echo "$CLIENT_CTX" | grep -q 'button="Middle" action="Press"'; then
    warn "Client context has 'Middle Press' binding — may interfere with middle-click paste"
    if [[ "$MODE" == "--fix" ]] || [[ "$FORCE" -eq 1 ]]; then
      python3 -c "
import xml.etree.ElementTree as ET

tree = ET.parse('$RC_XML')
root = tree.getroot()

for mouse in root.findall('mouse'):
    for context in mouse.findall('context'):
        if context.get('name') == 'Client':
            to_remove = []
            for mb in context.findall('mousebind'):
                if mb.get('button') == 'Middle' and mb.get('action') == 'Press':
                    to_remove.append(mb)
            for mb in to_remove:
                context.remove(mb)

tree.write('$RC_XML', encoding='UTF-8', xml_declaration=True)
" 2>/dev/null && fixed "Removed 'Middle Press' binding from Client context" || warn "Could not auto-fix"
    fi
  else
    pass "Client context: no 'Middle Press' binding (OK)"
  fi
fi

# ============================================================
section "2. rc.xml — <default /> Mouse Tag"
# ============================================================

echo ""
info "Checking for <default /> in mouse section..."

# The <default /> tag tells labwc to use its built-in mouse bindings.
# In some labwc versions, defaults include Left Press on Client context.
if grep -q '<default />' "$RC_XML" 2>/dev/null; then
  warn "<default /> found in mouse section — labwc built-in defaults may include click-consuming bindings"
  echo -e "    ${DIM}If clicks are broken, replace <default /> with explicit bindings${NC}"
  echo -e "    ${DIM}The safe defaults are already in dotfiles/labwc/rc.xml${NC}"

  if [[ "$MODE" == "--fix" ]] || [[ "$FORCE" -eq 1 ]]; then
    # Check if the dotfiles source rc.xml has a clean mouse section
    if [[ -f "$DOTFILES_RC" ]]; then
      DOTFILES_CLIENT=$(sed -n '/<context name="Client">/,/<\/context>/p' "$DOTFILES_RC" 2>/dev/null || true)
      if ! echo "$DOTFILES_CLIENT" | grep -q 'button="Left" action="Press"'; then
        # Remove <default /> and keep explicit bindings
        python3 -c "
import re

with open('$RC_XML', 'r') as f:
    content = f.read()

# Remove <default /> lines from mouse section
content = re.sub(r'\s*<default />\s*\n?', '\n', content)

with open('$RC_XML', 'w') as f:
    f.write(content)
" 2>/dev/null && fixed "Removed <default /> from mouse section (using explicit bindings)" || warn "Could not remove <default />"
      fi
    fi
  fi
else
  pass "No <default /> in mouse section (OK — using explicit bindings)"
fi

# ============================================================
section "3. rc.xml — Frame & All Mouse Contexts Audit"
# ============================================================

echo ""
info "Auditing all mouse contexts for click-consuming bindings..."

# Check Frame context — Left Press in Frame captures clicks for the ENTIRE
# window surface (client area included), breaking text selection and browsing
FRAME_CTX=$(sed -n '/<context name="Frame">/,/<\/context>/p' "$RC_XML" 2>/dev/null || true)
if echo "$FRAME_CTX" | grep -q 'button="Left" action="Press"'; then
  fail "Frame context has 'Left Press' — BREAKS clicks and text selection (Frame covers entire window surface)"
  if [[ "$MODE" == "--fix" ]] || [[ "$FORCE" -eq 1 ]]; then
    python3 -c "
import xml.etree.ElementTree as ET
import sys

tree = ET.parse('$RC_XML')
root = tree.getroot()

for mouse in root.findall('mouse'):
    for context in mouse.findall('context'):
        if context.get('name') == 'Frame':
            to_remove = []
            for mb in context.findall('mousebind'):
                if mb.get('button') == 'Left' and mb.get('action') == 'Press':
                    to_remove.append(mb)
            for mb in to_remove:
                context.remove(mb)

tree.write('$RC_XML', encoding='UTF-8', xml_declaration=True)
print('done')
" 2>/dev/null && fixed "Removed 'Left Press' binding from Frame context" || warn "Could not auto-fix Frame context"
  fi
else
  pass "Frame context: no Left Press (OK)"
fi

# Also check Frame context for Right Press/Resize — can interfere with context menus
if echo "$FRAME_CTX" | grep -q 'button="Right" action="Drag"'; then
  warn "Frame context has 'Right Drag' — may interfere with right-click context menus"
  if [[ "$MODE" == "--fix" ]] || [[ "$FORCE" -eq 1 ]]; then
    python3 -c "
import xml.etree.ElementTree as ET

tree = ET.parse('$RC_XML')
root = tree.getroot()

for mouse in root.findall('mouse'):
    for context in mouse.findall('context'):
        if context.get('name') == 'Frame':
            to_remove = []
            for mb in context.findall('mousebind'):
                if mb.get('button') == 'Right' and mb.get('action') == 'Drag':
                    to_remove.append(mb)
            for mb in to_remove:
                context.remove(mb)

tree.write('$RC_XML', encoding='UTF-8', xml_declaration=True)
" 2>/dev/null && fixed "Removed 'Right Drag' from Frame context" || warn "Could not auto-fix Frame context"
  fi
fi

# Check Titlebar context
TITLE_CTX=$(sed -n '/<context name="Titlebar">/,/<\/context>/p' "$RC_XML" 2>/dev/null || true)
if echo "$TITLE_CTX" | grep -q 'button="Left" action="Press"'; then
  pass "Titlebar context: Left Press (OK — this is for titlebar interactions)"
else
  info "Titlebar context: no Left Press"
fi

# Check Root context
ROOT_CTX=$(sed -n '/<context name="Root">/,/<\/context>/p' "$RC_XML" 2>/dev/null || true)
if echo "$ROOT_CTX" | grep -q 'button="Left" action="Press"'; then
  pass "Root context: Left Press (OK — this is for desktop right-click menu)"
else
  info "Root context: no Left Press"
fi

# ============================================================
section "4. Environment — Hardware Cursor Fix"
# ============================================================

echo ""
if [[ ! -f "$ENV_FILE" ]]; then
  warn "environment file not found at $ENV_FILE"
else
  if grep -q "^WLR_NO_HARDWARE_CURSORS=1" "$ENV_FILE"; then
    pass "WLR_NO_HARDWARE_CURSORS=1 is set (fixes cursor misalignment)"
  else
    fail "WLR_NO_HARDWARE_CURSORS=1 is NOT set — can cause click coordinates to be wrong"
    echo -e "    ${DIM}On some GPUs, hardware cursors report wrong positions to apps${NC}"
    echo -e "    ${DIM}This causes clicks to land in the wrong spot or not register${NC}"
    if [[ "$MODE" == "--fix" ]] || [[ "$FORCE" -eq 1 ]]; then
      echo "WLR_NO_HARDWARE_CURSORS=1" >> "$ENV_FILE"
      fixed "Added WLR_NO_HARDWARE_CURSORS=1 to environment"
    fi
  fi

  # Also check SEAT_BACKEND
  if grep -q "^SEAT_BACKEND=" "$ENV_FILE"; then
    pass "SEAT_BACKEND is set"
  else
    info "SEAT_BACKEND not set (optional — labwc auto-detects)"
  fi
fi

# ============================================================
section "5. Clipboard Daemon"
# ============================================================

echo ""
info "Checking clipboard support..."

if command -v wl-paste &>/dev/null; then
  pass "wl-paste found: $(command -v wl-paste)"
else
  fail "wl-paste not found — text selection copy/paste will not work"
  echo -e "    ${DIM}Install: sudo apt install wl-clipboard${NC}"
fi

if command -v wl-copy &>/dev/null; then
  pass "wl-copy found: $(command -v wl-copy)"
else
  fail "wl-copy not found — cannot copy selected text to clipboard"
  echo -e "    ${DIM}Install: sudo apt install wl-clipboard${NC}"
fi

if command -v cliphist &>/dev/null; then
  pass "cliphist found: $(command -v cliphist)"
else
  warn "cliphist not found (optional — clipboard history won't work)"
  echo -e "    ${DIM}Install: cargo install cliphist${NC}"
fi

  # Check if wl-paste daemon is running
  if pgrep -f "wl-paste.*cliphist" &>/dev/null; then
    pass "Clipboard daemon (wl-paste + cliphist) is running"
  elif pgrep -f "wl-paste" &>/dev/null; then
    pass "wl-paste daemon is running"
  else
    warn "No wl-paste daemon running — clipboard history won't persist"
    if [[ "$MODE" == "--fix" ]] || [[ "$FORCE" -eq 1 ]]; then
      if command -v cliphist &>/dev/null; then
        nohup wl-paste --type text/plain --watch cliphist store &>/dev/null &
        nohup wl-paste --type image --watch cliphist store &>/dev/null &
        disown
        fixed "Started wl-paste + cliphist daemon"
      elif command -v wl-paste &>/dev/null; then
        nohup wl-paste --type text/plain --watch cat &>/dev/null &
        disown
        fixed "Started wl-paste daemon (no cliphist)"
      fi
    else
      echo -e "    ${DIM}Start with: wl-paste --type text/plain --watch cliphist store &${NC}"
    fi
  fi

# ============================================================
section "6. Autostart Script"
# ============================================================

echo ""
if [[ ! -f "$AUTOSTART" ]]; then
  warn "autostart not found at $AUTOSTART"
else
  if [[ -x "$AUTOSTART" ]]; then
    pass "autostart is executable"
  else
    fail "autostart is NOT executable"
    if [[ "$MODE" == "--fix" ]] || [[ "$FORCE" -eq 1 ]]; then
      chmod +x "$AUTOSTART"
      fixed "Made autostart executable"
    fi
  fi

  # Check clipboard daemon in autostart
  if grep -q "cliphist\|wl-paste" "$AUTOSTART"; then
    pass "autostart: clipboard daemon configured"
  else
    warn "autostart: no clipboard daemon (wl-paste/cliphist) in autostart"
  fi
fi

# ============================================================
section "7. Validate dotfiles Source rc.xml"
# ============================================================

echo ""
if [[ -f "$DOTFILES_RC" ]]; then
  DOTFILES_CLIENT=$(sed -n '/<context name="Client">/,/<\/context>/p' "$DOTFILES_RC" 2>/dev/null || true)
  if echo "$DOTFILES_CLIENT" | grep -q 'button="Left" action="Press"'; then
    fail "Source rc.xml (dotfiles/) has 'Left Press' in Client context — will break clicks on fresh install"
  else
    pass "Source rc.xml (dotfiles/) Client context is clean"
  fi
else
  info "Source rc.xml not found at dotfiles/labwc/rc.xml"
fi

# ============================================================
section "8. Quick Click Test (runtime)"
# ============================================================

echo ""
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  info "Wayland session detected — runtime checks available"

  # Test wl-paste (with timeout to avoid hangs)
  if command -v wl-paste &>/dev/null; then
    if timeout 2 wl-paste 2>/dev/null | head -c 100; then
      echo ""
      pass "wl-paste can read clipboard"
    else
      info "Clipboard is empty (normal if nothing copied yet)"
    fi
  fi

  # Test wl-copy round-trip
  if command -v wl-copy &>/dev/null && command -v wl-paste &>/dev/null; then
    TEST_STR="labwc-click-test-$(date +%s)"
    echo -n "$TEST_STR" | wl-copy
    sleep 0.1
    PASTED=$(timeout 2 wl-paste 2>/dev/null || true)
    if [[ "$PASTED" == "$TEST_STR" ]]; then
      pass "Clipboard round-trip works (copy → paste)"
    else
      fail "Clipboard round-trip FAILED (copy → paste mismatch)"
    fi
    wl-copy -c 2>/dev/null || true
  fi
else
  info "No Wayland session — skipping runtime clipboard test"
  info "Run this script from within a labwc session to test clipboard"
fi

# ============================================================
section "Summary"
# ============================================================

echo ""
if [[ "$ISSUES" -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}No issues found! Click and text selection should work correctly.${NC}"
elif [[ "$FIXED" -gt 0 ]]; then
  echo -e "${GREEN}${BOLD}$FIXED issue(s) fixed${NC}, ${YELLOW}$((ISSUES - FIXED)) remaining${NC}"
  echo ""
  echo -e "  ${CYAN}Next step:${NC} Press ${BOLD}Alt+R${NC} (or ${BOLD}Super+R${NC}) to reload labwc"
else
  echo -e "${YELLOW}${BOLD}$ISSUES issue(s) found${NC} — run with ${BOLD}--fix${NC} to auto-fix"
fi
echo ""

if [[ "$ISSUES" -gt 0 && "$MODE" == "--check" ]]; then
  echo -e "  ${CYAN}To fix all issues:${NC} $0 --fix"
  echo ""
fi

exit "$ISSUES"
