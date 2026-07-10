#!/bin/bash
# -------------------------------------------------------------------
# OCWS Installer - Question-Driven Shell Selection
# Guides the user through picking their preferred desktop shell.
# For comprehensive distro-specific installation, use ./install-distribution.sh
# -------------------------------------------------------------------

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "\n${CYAN}==>${NC} $*"; }
pass() { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }
fail() { ocws_notify_error "OCWS Install" "$*"; echo -e "  ${RED}✗${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Centralized error handling + desktop notifications (ocws-notify / mako / dunst)
source "$SCRIPT_DIR/scripts/lib/ocws-err.sh"
ocws_enable_strict

check_requirements() {
    # Run the detailed requirements checker if available
    if [ -f "$SCRIPT_DIR/scripts/ocws-check-requirements.sh" ]; then
        bash "$SCRIPT_DIR/scripts/ocws-check-requirements.sh" 2>/dev/null
        local status=$?
        if [ $status -ne 0 ]; then
            echo ""
            echo -e "${YELLOW}Install missing dependencies, then run:${NC} ${GREEN}./install.sh${NC}"
            exit 1
        fi
    else
        # Fallback: minimal check
        info "Running Pre-Flight Check..."

        local missing=()
        if ! command -v git >/dev/null 2>&1; then missing+=("git"); fi
        if ! command -v labwc >/dev/null 2>&1; then missing+=("labwc"); fi
        if ! command -v sfwbar >/dev/null 2>&1; then missing+=("sfwbar"); fi
        if ! command -v fuzzel >/dev/null 2>&1; then missing+=("fuzzel"); fi

        if [ ${#missing[@]} -ne 0 ]; then
            echo -e "\n${RED}✗ Missing required dependencies:${NC}"
            for dep in "${missing[@]}"; do
                echo -e "    - ${YELLOW}$dep${NC}"
            done
            echo -e "\n  ${CYAN}Run: ./scripts/ocws-check-requirements.sh${NC}"
            echo -e "  ${CYAN}Or install manually and run ./install.sh again.${NC}"
            exit 1
        fi

        if ! command -v zig >/dev/null 2>&1; then
            echo -e "\n${YELLOW}⚠ zig not found — C binaries will use pre-built versions${NC}"
        fi

        pass "Core requirements met!"
    fi
}

# Run requirements check before proceeding
check_requirements

info "OCWS Shell Selection"

cat << 'MENU'

  Choose your desktop shell:

    1)  labwc + double-panel sfwbar
        ──────────────────────────────
        Dual-panel layout: top statusbar + bottom dock.
        Full OCWS shell — the standard experience.
        Statusbar + Dock via sfwbar.

    2)  labwc + sfwbar statusbar + crystal-dock
        ────────────────────────────────────────
        Single sfwbar statusbar on top.
        Application dock managed by crystal-dock.
        Classic panel + dock separation.

    3)  labwc + DankMaterialShell
        ────────────────────────────────────────
        Material Design-inspired shell by DankShrine.
        Vertical panel + minimalist layout.

    4)  labwc + Noctalia Shell
        ────────────────────────────────────────
        Quiet-by-design shell from the Noctalia project.
        Minimalist, distraction-free interface.

MENU

echo -n "  Enter choice [1-4] (default: 1): "
read -r mode_choice

case "${mode_choice:-1}" in
    1) MODE="doublepanel"
       MODE_DESC="labwc + double-panel sfwbar"
       ;;
    2) MODE="crystaldock"
       MODE_DESC="labwc + sfwbar statusbar + crystal-dock"
       ;;
    3) MODE="dms"
       MODE_DESC="labwc + DankMaterialShell"
       ;;
    4) MODE="noctalia"
       MODE_DESC="labwc + Noctalia Shell"
       ;;
    *) MODE="doublepanel"
       MODE_DESC="labwc + double-panel sfwbar"
       ;;
esac

echo -e "\n  Selected: ${CYAN}${MODE_DESC}${NC}"

echo -e "\n  Choose your default application launcher:"
echo -e "    1) fuzzel  (minimal, Wayland-native, runs out of the box)"
echo -e "    2) rofi    (feature-rich, customized theme)"
echo -n "  Enter choice [1-2] (default: 1): "
read -r launcher_choice

case "${launcher_choice:-1}" in
    2) LAUNCHER="rofi"
       LAUNCHER_DESC="rofi"
       ;;
    *) LAUNCHER="fuzzel"
       LAUNCHER_DESC="fuzzel"
       ;;
esac

echo -e "  Selected: ${CYAN}${LAUNCHER_DESC}${NC}"

TERMINAL="foot"
TERMINAL_DESC="foot"
echo -e "  Selected: ${CYAN}foot${NC}"

echo -e "\n  Use OCWS themed tmux configuration?"
echo -e "    Replaces your ~/.tmux.conf with a theme-aware config."
echo -e "    Your existing config will be backed up to dotfiles/tmux/tmux.conf.bak"
echo -n "  Enter choice [y/N] (default: N): "
read -r tmux_choice

case "${tmux_choice:-N}" in
    [Yy]) USE_TMUX=true ;;
    *)    USE_TMUX=false ;;
esac

echo -e "  Tmux config: ${CYAN}${USE_TMUX}${NC}"

echo -e "\n  Deploy single-file Neovim config?"
echo -e "    Installs a self-contained ~/.config/nvim/init.lua with lazy.nvim,"
echo -e "    LSP/Mason integration, Telescope, Treesitter, and OCWS theme support."
echo -e "    Your existing config will be backed up to dotfiles/nvim/init.lua.bak"
echo -n "  Enter choice [y/N] (default: N): "
read -r nvim_choice

case "${nvim_choice:-N}" in
    [Yy]) USE_NVIM=true ;;
    *)    USE_NVIM=false ;;
esac

echo -e "  Neovim config: ${CYAN}${USE_NVIM}${NC}"

# -------------------------------------------------------------------
# Stage 3 — Mode-Aware Dependency Resolution
# -------------------------------------------------------------------

# Determine which engines are needed for this selection
CORE_ENGINES="labwc sfwbar $LAUNCHER"
SHELL_ENGINE=""
case "$MODE" in
    dms)        SHELL_ENGINE="dms" ;;
    crystaldock) SHELL_ENGINE="crystal-dock" ;;
    noctalia)   SHELL_ENGINE="sfwbar" ;;
esac

# Check current status of each engine
check_status() {
    command -v "$1" >/dev/null 2>&1 && echo "✓" || echo "✗"
}

echo -e "\n  ${CYAN}Engine Status:${NC}"
echo -e "    labwc        $(check_status labwc)"
echo -e "    sfwbar       $(check_status sfwbar)"
echo -e "    $LAUNCHER       $(check_status $LAUNCHER)"
echo -e "    $TERMINAL       $(check_status $TERMINAL)"
if [ -n "$SHELL_ENGINE" ]; then
    echo -e "    $SHELL_ENGINE  $(check_status $SHELL_ENGINE)"
fi

echo -e "\n  ${CYAN}How to proceed:${NC}"
echo -e "    1) Auto-setup — install packages from repos + build unfound deps"
echo -e "    2) Configs only — just deploy dotfiles (I'll handle deps)"
echo -n "  Enter choice [1-2] (default: 1): "
read -r dep_choice

case "${dep_choice:-1}" in
    1)
        # Auto-setup: distro packages first, then community builds
        if [ -f "${SCRIPT_DIR}/install-distribution.sh" ]; then
            echo -e "\n${CYAN}==>${NC} Installing packages from distro repos..."
            bash "${SCRIPT_DIR}/install-distribution.sh" || echo -e "  ${YELLOW}⚠${NC} Package install had issues, continuing..."
        else
            echo -e "\n${YELLOW}⚠${NC} Distro installer not found. Install packages manually:"
            echo -e "    ./install-distribution.sh"
            echo -e "    or see docs/distro-packages.md"
        fi

        # Mode-specific builds
        need_build=""
        if [ "$MODE" = "dms" ]; then
            ! command -v dms >/dev/null 2>&1 && need_build="$need_build dms"
        elif [ "$MODE" = "crystaldock" ]; then
            ! command -v crystal-dock >/dev/null 2>&1 && need_build="$need_build crystal-dock"
        fi

        if [ -n "$need_build" ]; then
            echo -e "\n${YELLOW}⚠${NC} Unfound engines:${need_build}"
            echo -n "  Build them from source now? [y/N]: "
            read -r build_now
            if [[ "$build_now" =~ ^[Yy]$ ]] && [ -f "${SCRIPT_DIR}/build-ocws-core.sh" ]; then
                for engine in $need_build; do
                    bash "${SCRIPT_DIR}/build-ocws-core.sh" "$engine"
                done
            else
                for engine in $need_build; do
                    case "$engine" in
                        dms)
                            echo -e "  dms:    git clone https://github.com/DankShrine/dms.git && cd dms && make && sudo make install"
                            ;;
                        crystal-dock)
                            echo -e "  crystal-dock: see https://github.com/crystal-dock/crystal-dock"
                            ;;
                    esac
                done
            fi
        fi
        ;;
    *)
        echo -e "\n${YELLOW}⚠${NC} Skipping dependency installation."
        echo -e "  Required engines you'll need to install manually:"
        for engine in labwc sfwbar $LAUNCHER $TERMINAL $SHELL_ENGINE; do
            [ -n "$engine" ] && ! command -v "$engine" >/dev/null 2>&1 && echo -e "    - $engine"
        done
        echo -e "  See: docs/distro-packages.md"
        ;;
esac

# -------------------------------------------------------------------
# Deploy Configurations
# -------------------------------------------------------------------

# Pre-deploy confirmation
echo -e "\n${YELLOW}⚠ WARNING: This will deploy configurations to ~/.config/ and ~/.local/bin/${NC}"
echo -e "  Mode: ${CYAN}${MODE_DESC}${NC}"
echo -e "  Launcher: ${CYAN}${LAUNCHER_DESC}${NC}"
echo -e "  Terminal: ${CYAN}${TERMINAL_DESC}${NC}"
echo -e "  Tmux config: ${CYAN}${USE_TMUX}${NC}"
echo -e "  Affected directories: labwc, ocws, foot, gtk-3.0, gtk-4.0, mako, qt6ct"
echo -e "  Neovim config: ${CYAN}${USE_NVIM}${NC}"

if [[ "$LAUNCHER" == "rofi" ]]; then
    echo -e "  ${CYAN}  rofi${NC}: ~/.config/rofi/"
fi

case "$MODE" in
    doublepanel)
        echo -e "  Shell: OCWS dual-panel (top bar + dock via sfwbar)"
        echo -e "  ${CYAN}  OCWS:${NC} full bar config, widgets, plugins, themes"
        ;;
    crystaldock)
        echo -e "  Shell: crystal-dock dock + sfwbar single statusbar"
        echo -e "  ${CYAN}  OCWS:${NC} single top statusbar via sfwbar-full.config"
        ;;
    dms)
        echo -e "  Shell: DankMaterialShell"
        echo -e "  ${CYAN}  OCWS:${NC} infrastructure only (no sfwbar bars)"
        ;;
    noctalia)
        echo -e "  Shell: Noctalia"
        echo -e "  ${CYAN}  OCWS:${NC} infrastructure only (no sfwbar bars)"
        ;;
esac

echo -n "  Deploy now? [y/N]: "
read -r confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "\n  Installation aborted."
    exit 0
fi

# 2. Setup Directories
info "Setting up configuration directories..."
mkdir -p ~/.config/labwc
mkdir -p ~/.config/rofi
mkdir -p ~/.config/ocws/plugins
mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
mkdir -p ~/.local/bin/actions

case "$MODE" in
    crystaldock) mkdir -p ~/.config/crystal-dock ;;
    dms)         mkdir -p ~/.config/DankMaterialShell ;;
    noctalia)    mkdir -p ~/.config/noctalia ;;
esac
pass "Directories created."

# 3. Deploy Labwc Core
info "Deploying Compositor Rules (labwc)..."
cp -r "$SCRIPT_DIR/dotfiles/labwc/"* ~/.config/labwc/ 2>/dev/null || fail "Failed to deploy labwc configurations"
pass "labwc configurations synced."

# 4. Deploy OCWS Shell (supporting infrastructure for all modes)
info "Deploying the OCWS Shell..."
case "$MODE" in
    doublepanel)
        # Full OCWS dual-panel bar config
        rsync -a --exclude='user.config' "$SCRIPT_DIR/dotfiles/ocws/" ~/.config/ocws/ 2>/dev/null || cp -r "$SCRIPT_DIR/dotfiles/ocws/"* ~/.config/ocws/ 2>/dev/null || fail "Failed to deploy OCWS shell"
        ;;
    crystaldock)
        # OCWS infrastructure + single top statusbar (no dock)
        rsync -a --exclude='user.config' --exclude='ocws.config' "$SCRIPT_DIR/dotfiles/ocws/" ~/.config/ocws/ 2>/dev/null || cp -r "$SCRIPT_DIR/dotfiles/ocws/"* ~/.config/ocws/ 2>/dev/null || fail "Failed to deploy OCWS shell"
        ;;
    *)
        # Supporting infrastructure only — no sfwbar bar config at all
        rsync -a --exclude='user.config' --exclude='ocws.config' --exclude='ocws.css' --exclude='theme.css' "$SCRIPT_DIR/dotfiles/ocws/" ~/.config/ocws/ 2>/dev/null || cp -r "$SCRIPT_DIR/dotfiles/ocws/"* ~/.config/ocws/ 2>/dev/null || fail "Failed to deploy OCWS shell"
        ;;
esac

if [ ! -f ~/.config/ocws/user.config ]; then
    cp "$SCRIPT_DIR/dotfiles/ocws/user.config" ~/.config/ocws/user.config 2>/dev/null || true
fi

echo "$MODE" > ~/.config/ocws/mode
echo "$LAUNCHER" > ~/.config/ocws/launcher
echo "$TERMINAL" > ~/.config/ocws/terminal
pass "OCWS infrastructure, mode ($MODE), launcher ($LAUNCHER), and terminal ($TERMINAL) synced."

# 5. Deploy shell-specific configs
case "$MODE" in
    crystaldock)
        if [ -d "$SCRIPT_DIR/dotfiles/crystal-dock" ]; then
            info "Deploying crystal-dock configuration..."
            rsync -a "$SCRIPT_DIR/dotfiles/crystal-dock/" ~/.config/crystal-dock/ 2>/dev/null || true
            pass "crystal-dock config synced."
        fi
        ;;
    dms)
        if [ -d "$SCRIPT_DIR/dotfiles/DankMaterialShell" ]; then
            info "Deploying Dank Material Shell configuration..."
            rsync -a "$SCRIPT_DIR/dotfiles/DankMaterialShell/" ~/.config/DankMaterialShell/ 2>/dev/null || true
            pass "Dank Material Shell config synced."
        fi
        ;;
    noctalia)
        if [ -d "$SCRIPT_DIR/dotfiles/noctalia" ]; then
            info "Deploying Noctalia configuration..."
            rsync -a "$SCRIPT_DIR/dotfiles/noctalia/" ~/.config/noctalia/ 2>/dev/null || true
            pass "Noctalia config synced."
        fi
        ;;
esac

# 6. Deploy Application Launcher
case "$LAUNCHER" in
    rofi)
        if [ -d "$SCRIPT_DIR/dotfiles/rofi" ]; then
            info "Deploying Application Launcher (rofi)..."
            mkdir -p ~/.config/rofi
            cp -r "$SCRIPT_DIR/dotfiles/rofi/"* ~/.config/rofi/ 2>/dev/null || fail "Failed to deploy rofi configuration"
            pass "Rofi synced."
        fi
        ;;
    fuzzel)
        info "Deploying Fuzzel configuration..."
        mkdir -p ~/.config/fuzzel
        cp -r "$SCRIPT_DIR/dotfiles/fuzzel/"* ~/.config/fuzzel/ 2>/dev/null || true
        pass "Fuzzel synced."
        ;;
esac

# Deploy Terminal
case "$TERMINAL" in
    foot)
        if [ -d "$SCRIPT_DIR/dotfiles/foot" ]; then
            info "Deploying Foot Terminal configuration..."
            mkdir -p ~/.config/foot
            cp -r "$SCRIPT_DIR/dotfiles/foot/"* ~/.config/foot/ 2>/dev/null || true
            pass "Foot synced."
        fi
        ;;

esac

# Deploy Tmux
if [ "$USE_TMUX" = true ]; then
    info "Deploying OCWS Tmux configuration..."
    if [ -f ~/.tmux.conf ]; then
        cp ~/.tmux.conf "$SCRIPT_DIR/dotfiles/tmux/tmux.conf.bak" 2>/dev/null || true
        pass "Existing tmux.conf backed up to dotfiles/tmux/tmux.conf.bak"
    fi
    mkdir -p ~/.config/tmux
    if [ -f "$SCRIPT_DIR/dotfiles/tmux/tmux.conf" ]; then
        cp "$SCRIPT_DIR/dotfiles/tmux/tmux.conf" ~/.tmux.conf 2>/dev/null || true
        pass "OCWS tmux.conf deployed."
    fi
fi

# Deploy Neovim
if [ "$USE_NVIM" = true ]; then
    info "Deploying OCWS Neovim configuration..."
    if [ -f ~/.config/nvim/init.lua ]; then
        mkdir -p "$SCRIPT_DIR/dotfiles/nvim"
        cp ~/.config/nvim/init.lua "$SCRIPT_DIR/dotfiles/nvim/init.lua.bak" 2>/dev/null || true
        pass "Existing init.lua backed up to dotfiles/nvim/init.lua.bak"
    fi
    mkdir -p ~/.config/nvim
    if [ -f "$SCRIPT_DIR/dotfiles/nvim/init.lua" ]; then
        cp "$SCRIPT_DIR/dotfiles/nvim/init.lua" ~/.config/nvim/init.lua 2>/dev/null || true
        pass "OCWS nvim/init.lua deployed."
    fi
fi

# 7. Deploy GTK Styling
if [ -d "$SCRIPT_DIR/dotfiles/gtk-3.0" ] || [ -d "$SCRIPT_DIR/dotfiles/gtk-4.0" ] || [ -d "$SCRIPT_DIR/dotfiles/gtk" ]; then
    info "Deploying GTK Preferences..."
    mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
    [ -d "$SCRIPT_DIR/dotfiles/gtk" ] && cp -r "$SCRIPT_DIR/dotfiles/gtk/"* ~/.config/gtk-3.0/ 2>/dev/null || true
    [ -d "$SCRIPT_DIR/dotfiles/gtk" ] && cp -r "$SCRIPT_DIR/dotfiles/gtk/"* ~/.config/gtk-4.0/ 2>/dev/null || true
    [ -d "$SCRIPT_DIR/dotfiles/gtk-3.0" ] && cp -r "$SCRIPT_DIR/dotfiles/gtk-3.0/"* ~/.config/gtk-3.0/ 2>/dev/null || true
    [ -d "$SCRIPT_DIR/dotfiles/gtk-4.0" ] && cp -r "$SCRIPT_DIR/dotfiles/gtk-4.0/"* ~/.config/gtk-4.0/ 2>/dev/null || true
    pass "GTK settings synced."
fi

# Deploy Mako
if [ -d "$SCRIPT_DIR/dotfiles/mako" ]; then
    info "Deploying Mako configuration..."
    mkdir -p ~/.config/mako
    cp -r "$SCRIPT_DIR/dotfiles/mako/"* ~/.config/mako/ 2>/dev/null || true
    pass "Mako synced."
fi

# Deploy qt6ct
if [ -d "$SCRIPT_DIR/dotfiles/qt6ct" ]; then
    info "Deploying Qt6ct configuration..."
    mkdir -p ~/.config/qt6ct
    cp -r "$SCRIPT_DIR/dotfiles/qt6ct/"* ~/.config/qt6ct/ 2>/dev/null || true
    pass "Qt6ct synced."
fi

# 8. Deploy Compiled C Binaries
info "Deploying compiled OCWS binaries..."
if [ -d "$SCRIPT_DIR/zig-out/bin" ]; then
    mkdir -p ~/.local/bin
    cp -r "$SCRIPT_DIR/zig-out/bin/"* ~/.local/bin/ 2>/dev/null || true
    
    # Ensure they are executable
    chmod +x ~/.local/bin/ocws-* 2>/dev/null || true
    
    pass "Compiled C binaries installed to ~/.local/bin/."
else
    warn "zig-out/bin not found. Run 'zig build' first if you want C utilities installed."
fi

echo -e "\n${GREEN}OCWS Installation Complete!${NC}"
echo -e "You may need to log out and log back in, or restart your Wayland compositor."

