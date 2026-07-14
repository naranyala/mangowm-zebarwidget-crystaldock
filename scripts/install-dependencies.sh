#!/bin/bash
# ==============================================================================
# script: install-dependencies.sh
# description: Unified dependency installer for OCWS Dotfiles Environment
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "\n${CYAN}${BOLD}[*] $1${NC}"; }
pass()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# 1. Distro Package Manager
# ==============================================================================
info "Resolving system packages via Package Manager..."

# We define arrays of essential packages for different managers.
# OpenMandriva specific libraries are heavily lib64* prefixed.
if command -v dnf &>/dev/null; then
    PM="dnf install -y"
    PKGS=(
        # Core Wayland & DE
        labwc sfwbar rofi fuzzel foot mako dunst swaybg swayidle swaylock qt6ct
        wl-clipboard grim slurp cliphist brightnessctl playerctl
        # Core Utils
        git curl wget jq inotify-tools bc tesseract rsync unzip tar ripgrep fd-find
        # Build Tools & Languages
        gcc make cmake meson ninja pkg-config zig neovim nodejs python3-pip cargo
        # Development Libraries for C programs
        lib64gtk+3-devel lib64glib2.0-devel lib64gtk-layer-shell-devel lib64cairo-devel 
        lib64wayland-client-devel lib64pulseaudio-devel lib64lept-devel lib64tesseract-devel
        lib64Qt6QuickControls2-devel lib64Qt6ShaderTools-devel lib64Qt6Svg lib64Qt6Svg-devel qt6-qtwayland lib64Qt6WaylandClient-devel lib64Qt6WaylandCompositor-devel
    )
elif command -v apt-get &>/dev/null; then
    PM="apt-get install -y"
    PKGS=(
        labwc sfwbar rofi fuzzel foot mako-notifier dunst swaybg swayidle swaylock qt6ct
        wl-clipboard grim slurp cliphist brightnessctl playerctl
        git curl wget jq inotify-tools bc tesseract-ocr rsync unzip tar ripgrep fd-find
        gcc make cmake meson ninja-build pkg-config neovim nodejs npm python3-pip cargo
        libgtk-3-dev libglib2.0-dev libgtk-layer-shell-dev libcairo2-dev libqt6svg6-dev
        libwayland-dev libpulse-dev libleptonica-dev libtesseract-dev
    )
elif command -v pacman &>/dev/null; then
    PM="pacman -S --needed --noconfirm"
    PKGS=(
        labwc sfwbar rofi fuzzel foot mako dunst swaybg swayidle swaylock qt6ct
        wl-clipboard grim slurp cliphist brightnessctl playerctl
        git curl wget jq inotify-tools bc tesseract rsync unzip tar ripgrep fd
        gcc make cmake meson ninja pkgconf zig neovim nodejs npm python-pip cargo
        gtk3 glib2 gtk-layer-shell cairo qt6-svg wayland libpulse leptonica tesseract
    )
else
    fail "Unsupported package manager. Please install dependencies manually."
fi

sudo $PM "${PKGS[@]}" || warn "Some system packages failed to install. Continuing..."

# ==============================================================================
# 2. Homebrew (Cross-Distro CLI tools)
# ==============================================================================
info "Resolving cross-distro CLI tools via Homebrew..."

if ! command -v brew &>/dev/null; then
    warn "Homebrew is not installed. Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Try to load brew into current session
    if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
fi

if command -v brew &>/dev/null; then
    pass "Homebrew is available."
    brew install stow eza bat zoxide starship fzf
else
    warn "Homebrew installation failed or not in PATH. Skipping brew packages."
fi

# ==============================================================================
# 3. Flatpak (GUI Applications)
# ==============================================================================
info "Resolving GUI applications via Flatpak..."

if command -v flatpak &>/dev/null; then
    # Add flathub if missing
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
    
    FLATPAKS=(
        "org.mozilla.firefox"
        # "com.discordapp.Discord"
    )
    
    for app in "${FLATPAKS[@]}"; do
        if ! flatpak list | grep -q "$app"; then
            echo "Installing Flatpak: $app"
            flatpak install -y flathub "$app" || warn "Failed to install $app via Flatpak"
        else
            pass "Flatpak $app is already installed."
        fi
    done
else
    warn "Flatpak is not installed. Skipping GUI apps."
fi

# ==============================================================================
# 4. Git Repositories / Build from Source
# ==============================================================================
info "Resolving source-built tools..."

# 4.1 Contour Terminal
if ! command -v contour &>/dev/null; then
    echo "Contour terminal is missing. Executing build script..."
    if [ -f "$SCRIPT_DIR/install-contour.sh" ]; then
        bash "$SCRIPT_DIR/install-contour.sh" || warn "Contour installation failed."
    else
        warn "install-contour.sh not found in $SCRIPT_DIR!"
    fi
else
    pass "Contour terminal is already installed."
fi

# ==============================================================================
info "✅ All dependencies resolved!"
echo "Run ./scripts/ocws-check-requirements.sh or ./scripts/ocws-deps.sh to verify your system state."
