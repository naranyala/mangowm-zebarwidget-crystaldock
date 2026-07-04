#!/bin/bash
#
# install-screenshot-tools.sh — Install screenshot tools (ksnip, swappy, satty)
#
# For apt packages: uses pkexec (graphical) or sudo.
# Run from a labwc session for pkexec auth.
#

set -euo pipefail

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
section() { echo -e "\n${BOLD}[$1]${NC}"; }

echo ""
echo -e "${BOLD}Installing Screenshot Tools${NC}"
echo ""

# ============================================================
section "1. Check existing tools"
# ============================================================

echo ""
for tool in grim slurp flameshot gnome-screenshot scrot ksnip swappy satty; do
  if command -v "$tool" &>/dev/null; then
    pass "$tool: installed"
  else
    info "$tool: not installed"
  fi
done

# ============================================================
section "2. Install via apt"
# ============================================================

echo ""

# Build list of missing packages
PKGS=()
for pkg in ksnip swappy; do
  if dpkg -s "$pkg" &>/dev/null 2>&1; then
    pass "$pkg: already installed"
  elif apt-cache show "$pkg" &>/dev/null 2>&1; then
    PKGS+=("$pkg")
  else
    warn "$pkg: not in repository"
  fi
done

if [[ ${#PKGS[@]} -eq 0 ]]; then
  pass "All packages already installed"
else
  info "To install: ${PKGS[*]}"
  echo ""
  echo -e "  Run from a labwc session (for pkexec auth):"
  echo -e "    ${DIM}pkexec apt install -y ${PKGS[*]}${NC}"
  echo ""
  echo -e "  Or with sudo:"
  echo -e "    ${DIM}sudo apt install -y ${PKGS[*]}${NC}"
  echo ""

  # Try non-interactive install
  if pkexec apt-get install -y -qq "${PKGS[@]}" 2>/dev/null; then
    pass "Packages installed via pkexec"
  elif sudo apt-get install -y -qq "${PKGS[@]}" 2>/dev/null; then
    pass "Packages installed via sudo"
  else
    warn "Could not install automatically — run the command above"
  fi
fi

# ============================================================
section "3. Verify"
# ============================================================

echo ""
INSTALLED=0
for tool in ksnip swappy satty; do
  if command -v "$tool" &>/dev/null; then
    pass "$tool: ready"
    ((INSTALLED++))
  else
    warn "$tool: not available"
  fi
done

echo ""
echo -e "${GREEN}${BOLD}$INSTALLED annotation tool(s) ready${NC}"
echo ""
echo "Screenshot keybindings:"
echo "  Print            Area → clipboard"
echo "  Alt+Print        Full desktop → clipboard"
echo "  Super+Print      Full desktop → clipboard"
echo "  Ctrl+Print       Window → clipboard"
echo "  Super+Alt+Print  Area → annotate"
echo "  Super+Ctrl+Print Full → annotate"
echo ""
echo "Manual usage:"
echo "  grim -g \"\$(slurp)\" - | swappy -f -"
echo "  grim - | satty -"
echo "  ksnip"
echo ""
