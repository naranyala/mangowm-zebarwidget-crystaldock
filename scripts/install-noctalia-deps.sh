#!/bin/bash
#
# install-noctalia-deps.sh — Install Noctalia shell dependencies
#
# Auto-detects distro and installs via appropriate package manager.
# Supports: apt, dnf, pacman, zypper, xbps

set -euo pipefail

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
  elif command -v xbps-install &>/dev/null; then
    echo "xbps"
  else
    echo "unknown"
  fi
}

PKG_MGR=$(detect_pkg_manager)
info "Package manager: $PKG_MGR"

# ============================================================
section "Build Toolchain"
# ============================================================
case "$PKG_MGR" in
  apt)
    TOOLCHAIN_PKGS=(meson g++ pkg-config)
    ;;
  dnf)
    TOOLCHAIN_PKGS=(meson gcc-c++ pkgconf-pkg-config)
    ;;
  pacman)
    TOOLCHAIN_PKGS=(meson gcc pkgconf)
    ;;
  zypper)
    TOOLCHAIN_PKGS=(meson gcc-c++ pkg-config)
    ;;
  xbps)
    TOOLCHAIN_PKGS=(meson ninja pkg-config git)
    ;;
  *)
    fail "Unsupported package manager: $PKG_MGR"
    ;;
esac

# just command runner — install standalone if not present
info "Checking just command runner..."
if command -v just &>/dev/null; then
  pass "just: $(command -v just)"
else
  info "Installing just via standalone installer..."
  mkdir -p "$HOME/.local/bin"
  curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to "$HOME/.local/bin" 2>/dev/null
  if [ -f "$HOME/.local/bin/just" ]; then
    pass "just installed to ~/.local/bin/just"
    export PATH="$HOME/.local/bin:$PATH"
  else
    fail "Failed to install just"
  fi
fi

# ============================================================
section "Wayland & OpenGL Dependencies"
# ============================================================
case "$PKG_MGR" in
  apt)
    WAYLAND_PKGS=(
      libwayland-dev wayland-protocols
      libegl-dev libgles-dev
      libxkbcommon-dev
    )
    ;;
  dnf)
    WAYLAND_PKGS=(
      wayland-devel wayland-protocols-devel
      libEGL-devel mesa-libGLES-devel
      libxkbcommon-devel
    )
    ;;
  pacman)
    WAYLAND_PKGS=(
      wayland wayland-protocols
      libglvnd
      libxkbcommon
    )
    ;;
  zypper)
    WAYLAND_PKGS=(
      wayland-devel wayland-protocols-devel
      Mesa-libEGL-devel Mesa-libGLESv2-devel
      libxkbcommon-devel
    )
    ;;
  xbps)
    WAYLAND_PKGS=(
      wayland-devel wayland-protocols
      mesa-libEGL-devel
      libxkbcommon-devel
    )
    ;;
esac

# ============================================================
section "Font & Text Rendering"
# ============================================================
case "$PKG_MGR" in
  apt)
    FONT_PKGS=(
      libfreetype-dev libfontconfig-dev
      libcairo2-dev libpango1.0-dev libharfbuzz-dev
    )
    ;;
  dnf)
    FONT_PKGS=(
      freetype-devel fontconfig-devel
      cairo-devel pango-devel harfbuzz-devel
    )
    ;;
  pacman)
    FONT_PKGS=(
      freetype2 fontconfig
      cairo pango harfbuzz
    )
    ;;
  zypper)
    FONT_PKGS=(
      freetype2-devel fontconfig-devel
      cairo-devel pango-devel harfbuzz-devel
    )
    ;;
  xbps)
    FONT_PKGS=(
      freetype-devel fontconfig-devel
      cairo-devel pango-devel harfbuzz-devel
    )
    ;;
esac

# ============================================================
section "Core Libraries"
# ============================================================
case "$PKG_MGR" in
  apt)
    CORE_PKGS=(
      libglib2.0-dev
      libsdbus-c++-dev
      libpipewire-0.3-dev libwireplumber-0.5-dev
      libpam0g-dev
      libpolkit-agent-1-dev libpolkit-gobject-1-dev
    )
    ;;
  dnf)
    CORE_PKGS=(
      glib2-devel
      sdbus-cpp-devel
      pipewire-devel wireplumber-devel
      pam-devel polkit-devel
    )
    ;;
  pacman)
    CORE_PKGS=(
      glib2
      sdbus-cpp
      pipewire wireplumber
      pam polkit
    )
    ;;
  zypper)
    CORE_PKGS=(
      glib2-devel
      sdbus-cpp-devel
      pipewire-devel wireplumber-devel
      pam-devel polkit-devel
    )
    ;;
  xbps)
    CORE_PKGS=(
      glib-devel
      basu-devel sdbus-c++-devel
      pipewire-devel wireplumber-devel
      pam-devel polkit-devel
    )
    ;;
esac

# ============================================================
section "Media & Image Libraries"
# ============================================================
case "$PKG_MGR" in
  apt)
    MEDIA_PKGS=(
      libcurl4-openssl-dev
      libwebp-dev librsvg2-dev
    )
    ;;
  dnf)
    MEDIA_PKGS=(
      libcurl-devel libwebp-devel librsvg2-devel
    )
    ;;
  pacman)
    MEDIA_PKGS=(
      curl libwebp librsvg
    )
    ;;
  zypper)
    MEDIA_PKGS=(
      libcurl-devel libwebp-devel librsvg-devel
    )
    ;;
  xbps)
    MEDIA_PKGS=(
      libcurl-devel libwebp-devel librsvg-devel
    )
    ;;
esac

# ============================================================
section "Optional Libraries"
# ============================================================
case "$PKG_MGR" in
  apt)
    OPTIONAL_PKGS=(
      libqalculate-dev libxml2-dev
      libjemalloc-dev
    )
    ;;
  dnf)
    OPTIONAL_PKGS=(
      libqalculate-devel libxml2-devel
      jemalloc-devel
    )
    ;;
  pacman)
    OPTIONAL_PKGS=(
      libqalculate libxml2
      jemalloc
    )
    ;;
  zypper)
    OPTIONAL_PKGS=(
      libqalculate-devel libxml2-devel
      jemalloc-devel
    )
    ;;
  xbps)
    OPTIONAL_PKGS=(
      libqalculate-devel libxml2-devel
      jemalloc-devel
    )
    ;;
esac

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
    xbps)
      sudo xbps-install -Sy "${pkgs[@]}" 2>/dev/null
      ;;
  esac
}

ALL_PKGS=(
  "${TOOLCHAIN_PKGS[@]}"
  "${WAYLAND_PKGS[@]}"
  "${FONT_PKGS[@]}"
  "${CORE_PKGS[@]}"
  "${MEDIA_PKGS[@]}"
  "${OPTIONAL_PKGS[@]}"
)

info "Total packages: ${#ALL_PKGS[@]}"
info "Installing all Noctalia dependencies..."

if install_pkgs "${ALL_PKGS[@]}"; then
  pass "All dependencies installed"
else
  warn "Some packages may have failed — check output above"
fi

# ============================================================
section "Verifying Installation"
# ============================================================
REQUIRED_BINS=(meson g++ pkg-config)
REQUIRED_LIBS=(wayland freetype cairo pango harfbuzz xkbcommon glib-2.0 sdbus-c++)

for bin in "${REQUIRED_BINS[@]}"; do
  if command -v "$bin" &>/dev/null; then
    pass "$bin: $(command -v "$bin")"
  else
    warn "$bin: not found"
  fi
done

for lib in "${REQUIRED_LIBS[@]}"; do
  if pkg-config --exists "$lib" 2>/dev/null; then
    pass "lib $lib: found"
  else
    warn "lib $lib: not found"
  fi
done

# ============================================================
section "Summary"
# ============================================================
echo ""
pass "Noctalia shell dependencies ready"
echo ""
echo "Next steps:"
echo "  1. Clone Noctalia:   git clone --depth 1 https://github.com/noctalia-dev/noctalia.git build/noctalia-src"
echo "  2. Configure:         cd build/noctalia-src && just configure release ~/.local"
echo "  3. Build:             just build release"
echo "  4. Install:           sudo just install release"
echo "  5. Configure:         cp build/noctalia-src/example.toml ~/.config/noctalia/config.toml"
echo ""
