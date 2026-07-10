#!/bin/bash
#
# install-contour.sh — Download, build, and install Contour terminal from source.
#
# Contour is a modern, GPU-accelerated terminal emulator with C++20 core.
# This script clones the latest master, resolves system dependencies per
# distro, builds with CMake + Ninja, and installs to /usr/local.
#
# Usage:
#   ./scripts/install-contour.sh             # Full build + install
#   ./scripts/install-contour.sh deps        # Install system deps only
#   ./scripts/install-contour.sh verify      # Check if contour is ready
#

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

pass()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; }
info()    { echo -e "  ${CYAN}→${NC} $1"; }
fail()    { echo -e "  ${RED}✗${NC} $1"; exit 1; }
section() { echo -e "\n${BOLD}[$1]${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"
BUILD_DIR="/tmp/ocws-contour-build"
REPO_URL="https://github.com/contour-terminal/contour.git"

elevate() {
  if command -v pkexec &>/dev/null; then pkexec "$@"
  elif command -v sudo &>/dev/null; then sudo "$@"
  else fail "Neither pkexec nor sudo available."; fi
}

detect_pm() {
  if command -v apt-get &>/dev/null; then echo "apt"
  elif command -v pacman &>/dev/null; then echo "pacman"
  elif command -v dnf &>/dev/null; then echo "dnf"
  elif command -v zypper &>/dev/null; then echo "zypper"
  elif command -v apk &>/dev/null; then echo "apk"
  else echo "unknown"; fi
}

install_pkgs() {
  local pm; pm="$(detect_pm)"
  info "Installing packages via $pm: $*"
  case "$pm" in
    apt)     elevate sh -c "apt-get update -qq && apt-get install -y -qq $*" ;;
    pacman)  elevate pacman -S --needed --noconfirm "$@" ;;
    dnf)     elevate dnf install -y "$@" ;;
    zypper)  elevate zypper --non-interactive install "$@" ;;
    apk)     elevate apk add "$@" ;;
    *)       warn "Unknown PM — install manually: $*"; return 1 ;;
  esac
}

# ============================================================
section "1. Prerequisites"
# ============================================================

echo ""

MISSING_PREREQS=()
for cmd in git cmake ninja pkg-config gcc g++; do
  command -v "$cmd" &>/dev/null || MISSING_PREREQS+=("$cmd")
done

if ! command -v c++ &>/dev/null && ! command -v g++ &>/dev/null && ! command -v clang++ &>/dev/null; then
  MISSING_PREREQS+=("c++-compiler")
fi

if [[ ${#MISSING_PREREQS[@]} -gt 0 ]]; then
  warn "Missing build tools: ${MISSING_PREREQS[*]}"
  install_pkgs "git cmake ninja-build pkg-config gcc g++"
fi

# Check C++20 support
CXX=""
for candidate in clang++ g++; do
  if command -v "$candidate" &>/dev/null; then
    CXX="$candidate"
    break
  fi
done

if [[ -n "$CXX" ]]; then
  CXX_STD=$("$CXX" -dM -E -x c++ /dev/null 2>/dev/null | grep __cplusplus | awk '{print $3}' | tr -d 'L' || echo "0")
  if [[ "$CXX_STD" -ge 202002 ]]; then
    pass "$CXX supports C++20 ($CXX_STD)"
  else
    warn "$CXX reports C++ standard $CXX_STD (need >= 202002L). Upgrade your compiler."
  fi
fi

# ============================================================
section "2. System Dependencies"
# ============================================================

echo ""

PM="$(detect_pm)"
case "$PM" in
  apt)
    DEPS=(libyaml-cpp-dev libfontconfig1-dev libharfbuzz-dev libfreetype-dev
           liblcms2-dev libpng-dev libxkbcommon-dev libutempter-dev
           libfmt-dev mesa-common-dev libgl1-mesa-dev
           cmake ninja-build)
    ;;
  pacman)
    DEPS=(yaml-cpp fontconfig harfbuzz freetype2 lcms2 libpng libxkbcommon
          libutempter fmt mesa cmake ninja)
    ;;
  dnf)
    DEPS=(yaml-cpp-devel fontconfig-devel harfbuzz-devel freetype-devel
          lcms2-devel libpng-devel libxkbcommon-devel libutempter-devel
          fmt-devel mesa-libGL-devel cmake ninja-build
          qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtmultimedia-devel
          qt6-qtbase-private-devel qt6-qtshadertools-devel)
    ;;
  zypper)
    DEPS=(libyaml-cpp-devel fontconfig-devel harfbuzz-devel freetype2-devel
          lcms2-devel libpng-devel libxkbcommon-devel libutempter-devel
          fmt-devel Mesa-devel cmake ninja)
    ;;
  apk)
    DEPS=(yaml-cpp-dev fontconfig-dev harfbuzz-dev freetype-dev
          lcms2-dev libpng-dev libxkbcommon-dev libutempter-dev
          fmt-dev mesa-dev cmake ninja)
    ;;
  *)
    warn "Unsupported PM. Install contour via distro packages or flatpak:"
    echo -e "    ${DIM}sudo pacman -S contour${NC}"
    echo -e "    ${DIM}sudo apt install contour${NC}"
    echo -e "    ${DIM}flatpak install flathub org.contourterminal.Contour${NC}"
    exit 0
    ;;
esac

install_pkgs "${DEPS[@]}"

# ============================================================
section "3. Build Contour from Source"
# ============================================================

echo ""

if command -v contour &>/dev/null; then
  pass "contour binary already installed ($(contour --version 2>/dev/null || true))"
  echo -e "    Rebuild? Remove it first: ${DIM}elevate rm \"\$(which contour)\"${NC}"
  echo ""
fi

info "Cloning $REPO_URL"
rm -rf "$BUILD_DIR"
git clone --depth=1 --recursive "$REPO_URL" "$BUILD_DIR"
cd "$BUILD_DIR"

info "Configuring with CMake"
mkdir -p build && cd build
cmake .. -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCONTOUR_USE_BUNDLED_FMT=OFF \
  -DCONTOUR_USE_BUNDLED_RANGE_V3=OFF \
  -DCONTOUR_USE_BUNDLED_LIBUNICODE=OFF

info "Compiling Contour (this may take a while)..."
ninja -j"$(nproc)"

info "Installing to $PREFIX"
elevate ninja install

cd /
rm -rf "$BUILD_DIR"

# ============================================================
section "4. Verify"
# ============================================================

echo ""

if command -v contour &>/dev/null; then
  pass "Contour installed: $(contour --version 2>/dev/null || contour version 2>/dev/null || echo "$PREFIX/bin/contour")"
else
  warn "contour binary not found in PATH after install"
  echo -e "    Check: ${DIM}$PREFIX/bin/contour${NC}"
  echo -e "    Add to PATH if needed: ${DIM}export PATH=\"\$PATH:$PREFIX/bin\"${NC}"
fi

echo ""
echo -e "${GREEN}${BOLD}Contour terminal build complete!${NC}"
echo ""
echo "Configuration is managed by OCWS:"
echo "  theme-engine.sh apply <theme>   → generates ~/.config/contour/contour.yml"
echo "  install.sh                      → deploys dotfiles/contour/contour.yml"
echo "Manual:"
echo "  contour --help"
echo "  man contour"
