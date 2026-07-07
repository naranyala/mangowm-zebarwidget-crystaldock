#!/bin/bash
# -------------------------------------------------------------------
# OCWS Core Builder
# Fetches the absolute latest master branch of the 3 engines and builds them.
# -------------------------------------------------------------------

set -euo pipefail

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "\n${CYAN}==> $*${NC}"; }
pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; exit 1; }

# Prerequisites Check
for cmd in git meson ninja pkg-config gcc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        fail "Missing required build tool: $cmd"
    fi
done

PREFIX="${PREFIX:-/usr/local}"
BUILD_DIR="/tmp/ocws-build"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

build_engine() {
    local NAME=$1
    local REPO_URL=$2

    info "Building $NAME from $REPO_URL"

    # Clean previous build
    rm -rf "$NAME"
    
    # Fetch absolute latest
    git clone --depth=1 "$REPO_URL" "$NAME"
    cd "$NAME"

    # Meson Build
    info "Configuring $NAME..."
    meson setup build --prefix="$PREFIX" --buildtype=release
    
    info "Compiling $NAME..."
    ninja -C build

    info "Installing $NAME..."
    pkexec sh -c "cd \"$PWD\" && ninja -C build install"

    cd ..
    pass "$NAME successfully installed to $PREFIX!"
}

# ============================================================
# Core Engines
# ============================================================

case "${1:-all}" in
    "labwc")
        build_engine "labwc" "https://github.com/labwc/labwc.git"
        ;;
    "sfwbar")
        build_engine "sfwbar" "https://github.com/LBCrion/sfwbar.git"
        ;;
    "fuzzel")
        build_engine "fuzzel" "https://codeberg.org/dnkl/fuzzel.git"
        ;;
    "all")
        build_engine "labwc" "https://github.com/labwc/labwc.git"
        build_engine "sfwbar" "https://github.com/LBCrion/sfwbar.git"
        build_engine "fuzzel" "https://codeberg.org/dnkl/fuzzel.git"
        ;;
    *)
        fail "Unknown target: $1. Available: labwc, sfwbar, fuzzel, all"
        ;;
esac

info "OCWS Core Build Complete!"
echo -e "\n${YELLOW}Note:${NC} If you are using community shells like 'dms', 'noctalia', or 'crystal-dock', you will need to clone and build them manually from their respective repositories."
