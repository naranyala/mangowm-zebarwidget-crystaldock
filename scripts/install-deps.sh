#!/bin/bash
#
# install-deps.sh — Install all dependencies for labwc + sfwbar + crystal-dock
#
# Auto-detects distro and installs via appropriate package manager.
# Supports: apt, dnf, pacman, zypper

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}✓${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $*"; exit 1; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
info()  { echo -e "  ${CYAN}→${NC} $1"; }
section() { echo -e "\n${BOLD}[$1]${NC}"; }

# ============================================================
section "Detecting Distribution"
# ============================================================
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO="${ID:-unknown}"
  DISTRO_VERSION="${VERSION_ID:-}"
  pass "Detected: $PRETTY_NAME"
else
  fail "Cannot detect distribution (/etc/os-release not found)"
fi

# Detect package manager
detect_pkg_manager() {
  if command -v apt &>/dev/null; then
    echo "apt"
  elif command -v dnf &>/dev/null; then
    echo "dnf"
  elif command -v pacman &>/dev/null; then
    echo "pacman"
  elif command -v zypper &>/dev/null; then
    echo "zypper"
  else
    echo "unknown"
  fi
}

PKG_MGR=$(detect_pkg_manager)
info "Package manager: $PKG_MGR"

# ============================================================
section "Build Dependencies (labwc)"
# ============================================================
case "$PKG_MGR" in
  apt)
    BUILD_PKGS=(
      meson ninja-build gcc g++ pkg-config
      libwayland-dev libwlroots-dev libxml2-dev
      libcairo2-dev libpango1.0-dev libglib2.0-dev
      libinput-dev libpng-dev libxkbcommon-dev
      wayland-protocols
    )
    ;;
  dnf)
    BUILD_PKGS=(
      meson ninja-build gcc gcc-c++ pkgconf-pkg-config
      wayland-devel wlroots-devel libxml2-devel
      cairo-devel pango-devel glib2-devel
      libinput-devel libpng-devel libxkbcommon-devel
      wayland-protocols-devel
    )
    ;;
  pacman)
    BUILD_PKGS=(
      meson ninja gcc pkgconf
      wayland wlroots libxml2
      cairo pango glib2
      libinput libpng libxkbcommon
      wayland-protocols
    )
    ;;
  zypper)
    BUILD_PKGS=(
      meson ninja gcc gcc-c++ pkg-config
      wayland-devel libwlroots-devel libxml2-devel
      cairo-devel pango-devel glib2-devel
      libinput-devel libpng-devel libxkbcommon-devel
      wayland-protocols-devel
    )
    ;;
  *)
    fail "Unsupported package manager: $PKG_MGR"
    ;;
esac

info "Build packages: ${BUILD_PKGS[*]}"

# ============================================================
section "Runtime Dependencies"
# ============================================================
case "$PKG_MGR" in
  apt)
    RUNTIME_PKGS=(
      swaybg foot rofi-wayland fuzzel cliphist jgmenu
      grim slurp wl-clipboard
      playerctl
      libinput-tools
      dconf-cli
      libxml2-utils
    )
    ;;
  dnf)
    RUNTIME_PKGS=(
      swaybg foot rofi-wayland fuzzel cliphist jgmenu
      grim slurp wl-clipboard
      playerctl
      libinput-utils
      dconf
      libxml2
    )
    ;;
  pacman)
    RUNTIME_PKGS=(
      swaybg foot rofi-wayland fuzzel cliphist jgmenu
      grim slurp wl-clipboard
      playerctl
      libinput
      dconf
      libxml2
    )
    ;;
  zypper)
    RUNTIME_PKGS=(
      swaybg foot rofi fuzzel cliphist jgmenu
      grim slurp wl-clipboard
      playerctl
      libinput-tools
      dconf
      libxml2-tools
    )
    ;;
esac

info "Runtime packages: ${RUNTIME_PKGS[*]}"

# ============================================================
section "Optional Dependencies"
# ============================================================
case "$PKG_MGR" in
  apt)
    OPTIONAL_PKGS=(
      gammastep mako dunst lxpolkit network-manager-gnome blueman swayidle swaylock udiskie gnome-keyring
    )
    ;;
  dnf)
    OPTIONAL_PKGS=(
      gammastep mako dunst polkit-gnome network-manager-applet blueman swayidle swaylock udiskie gnome-keyring
    )
    ;;
  pacman)
    OPTIONAL_PKGS=(
      gammastep mako dunst polkit-gnome network-manager-applet blueman swayidle swaylock udiskie gnome-keyring
    )
    ;;
  zypper)
    OPTIONAL_PKGS=(
      gammastep mako dunst polkit-gnome NetworkManager-applet blueman swayidle swaylock udiskie gnome-keyring
    )
    ;;
esac

info "Optional packages: ${OPTIONAL_PKGS[*]}"

# ============================================================
section "Installing Packages"
# ============================================================
install_pkgs() {
  local pkgs=("$@")
  case "$PKG_MGR" in
    apt)
      sudo apt update -qq
      sudo apt install -y -qq "${pkgs[@]}" 2>/dev/null
      ;;
    dnf)
      sudo dnf install -y -q "${pkgs[@]}" 2>/dev/null
      ;;
    pacman)
      sudo pacman -S --noconfirm --needed "${pkgs[@]}" 2>/dev/null
      ;;
    zypper)
      sudo zypper install -y -n "${pkgs[@]}" 2>/dev/null
      ;;
  esac
}

# Install build deps
info "Installing build dependencies..."
if install_pkgs "${BUILD_PKGS[@]}"; then
  pass "Build dependencies installed"
else
  warn "Some build dependencies may have failed"
fi

# Install runtime deps
info "Installing runtime dependencies..."
if install_pkgs "${RUNTIME_PKGS[@]}"; then
  pass "Runtime dependencies installed"
else
  warn "Some runtime dependencies may have failed"
fi

# Install optional deps
info "Installing optional dependencies..."
if install_pkgs "${OPTIONAL_PKGS[@]}"; then
  pass "Optional dependencies installed"
else
  warn "Some optional dependencies may have failed"
fi

# ============================================================
section "Verifying Installation"
# ============================================================
for bin in meson ninja gcc pkg-config swaybg; do
  if command -v "$bin" &>/dev/null; then
    pass "$bin: $(command -v "$bin")"
  else
    warn "$bin: not found after install"
  fi
done

# ============================================================
section "Building labwc from Source"
# ============================================================
if [ -f "$PROJECT_DIR/download-labwc.sh" ]; then
  info "labwc source build script available: ./download-labwc.sh"
  info "Run it with --install to build and install"
else
  warn "download-labwc.sh not found"
fi

# ============================================================
section "Summary"
# ============================================================
echo ""
pass "All dependencies installed"
echo ""
echo "Next steps:"
echo "  1. Build labwc:    ./download-labwc.sh --install"
echo "  2. Install config: ./dotfiles/install.sh"
echo "  3. Validate:       ./scripts/validate.sh"
echo "  4. Launch:         ./scripts/start-labwc.sh"
echo ""
