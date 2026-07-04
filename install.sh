#!/bin/bash
# -------------------------------------------------------------------
# OCWS Installer
# The single elegant entrypoint for deploying the OCWS ecosystem.
# -------------------------------------------------------------------

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "\n${CYAN}==>${NC} $*"; }
pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info "Initializing OCWS Deployment..."

# 1. Dependency Check
if ! command -v labwc >/dev/null 2>&1 || ! command -v sfwbar >/dev/null 2>&1 || ! command -v fuzzel >/dev/null 2>&1; then
    echo -e "  ${RED}Warning:${NC} Core engines (labwc, sfwbar, fuzzel) are missing!"
    echo "  Please install them via your package manager or run: ./build-ocws-core.sh all"
    echo -e "  Press [ENTER] to continue anyway, or Ctrl+C to cancel."
    read -r
fi

# 2. Setup Directories
info "Setting up namespaces..."
mkdir -p ~/.config/labwc
mkdir -p ~/.config/ocws/plugins
mkdir -p ~/.config/fuzzel
mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
mkdir -p ~/.local/bin/actions
pass "Directories created."

# 3. Deploy Labwc Core
info "Deploying Compositor Rules (labwc)..."
cp -r "$SCRIPT_DIR/dotfiles/labwc/"* ~/.config/labwc/
pass "labwc configurations synced."

# 4. Deploy OCWS Shell
info "Deploying the OCWS Shell..."
cp -r "$SCRIPT_DIR/dotfiles/ocws/"* ~/.config/ocws/
pass "OCWS layout and plugins synced."

# 5. Deploy Fuzzel Launcher
if [ -d "$SCRIPT_DIR/dotfiles/fuzzel" ]; then
    info "Deploying Application Launcher (fuzzel)..."
    cp -r "$SCRIPT_DIR/dotfiles/fuzzel/"* ~/.config/fuzzel/
    pass "Fuzzel synced."
fi

# 6. Deploy GTK Styling
if [ -d "$SCRIPT_DIR/dotfiles/gtk" ]; then
    info "Deploying GTK Preferences..."
    cp -r "$SCRIPT_DIR/dotfiles/gtk/"* ~/.config/gtk-3.0/ 2>/dev/null || true
    cp -r "$SCRIPT_DIR/dotfiles/gtk/"* ~/.config/gtk-4.0/ 2>/dev/null || true
    pass "GTK settings synced."
fi

# 7. Deploy IPC & Core Tools
info "Deploying Event Bus API & System Tools..."
find "$SCRIPT_DIR/scripts" -maxdepth 1 -type f -name "*.sh" -exec cp {} ~/.local/bin/ \;
if [ -d "$SCRIPT_DIR/scripts/actions" ]; then
    cp "$SCRIPT_DIR/scripts/actions/"* ~/.local/bin/actions/ 2>/dev/null || true
fi
chmod +x ~/.local/bin/*.sh 2>/dev/null || true
chmod +x ~/.local/bin/actions/* 2>/dev/null || true
pass "Scripts and IPC mapped to ~/.local/bin"

# 8. Success
info "OCWS Deployment Complete! 🚀"
echo "Log out and select 'labwc' from your display manager, or type 'labwc' in your TTY."
