#!/bin/bash
# -------------------------------------------------------------------
# OCWS Audio Builder
# Fetches + builds the third-party sources that make ocws-equalizer a
# complete audio utility: the mbeq LADSPA EQ engine (swh-plugins), an
# optional cava visualizer, and verifies the system libs the GUI needs
# (libpulse, fftw3, cairo). EasyEffects is offered as an optional full
# backend.
#
# Mirrors the convention in build-ocws-core.sh (git clone -> build -> install).
# -------------------------------------------------------------------

set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
info()  { echo -e "\n${CYAN}==> $*${NC}"; }
pass()  { echo -e "  ${GREEN}✓${NC} $*"; }
fail()  { echo -e "  ${RED}✗${NC} $*"; exit 1; }
warn()  { echo -e "  ${YELLOW}!${NC} $*"; }

elevate() {
    if command -v pkexec &>/dev/null; then pkexec "$@"
    elif command -v sudo &>/dev/null; then sudo "$@"
    else fail "Neither pkexec nor sudo available."; fi
}

for cmd in git meson ninja pkg-config gcc make autoreconf autopoint; do
    command -v "$cmd" >/dev/null 2>&1 || warn "Build tool missing: $cmd (some targets need it)"
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"
BUILD_DIR="/tmp/ocws-audio-build"
mkdir -p "$BUILD_DIR"; cd "$BUILD_DIR"

# ---- Distro package install helper -------------------------------------
detect_pkg() {
    if command -v apt-get >/dev/null 2>&1;    then echo apt
    elif command -v pacman >/dev/null 2>&1;   then echo pacman
    elif command -v dnf >/dev/null 2>&1;      then echo dnf
    else echo unknown; fi
}

install_pkgs() {
    local pm; pm="$(detect_pkg)"
    info "Installing system packages via $pm: $*"
    case "$pm" in
        apt)     elevate sh -c "apt-get update && apt-get install -y $*";;
        pacman)  elevate pacman -S --needed --noconfirm "$@";;
        dnf)     elevate dnf install -y "$@";;
        *) warn "Unknown package manager; install these manually: $*";;
    esac
}

# Verify a pkg-config module; install dev package if missing.
need_pkg() {
    local mod="$1" pkg="$2"
    if pkg-config --exists "$mod"; then pass "$mod present ($(pkg-config --modversion "$mod"))"; return 0; fi
    warn "$mod missing — installing $pkg"
    install_pkgs "$pkg"
    pkg-config --exists "$mod" || fail "$mod still missing after install"
}

# ---- Generic builders ---------------------------------------------------
build_make() {
    local NAME=$1 REPO=$2
    info "Building $NAME from $REPO"
    rm -rf "$NAME"; git clone --depth=1 "$REPO" "$NAME"; cd "$NAME"
    if [ -x ./autogen.sh ]; then ./autogen.sh
    elif [ -x ./configure ]; then true
    elif [ -f configure.ac ] || [ -f configure.in ]; then autoreconf -fi; fi
    ./configure --prefix="$PREFIX"
    make -j"$(nproc)"
    elevate make install
    elevate sh -c "ldconfig 2>/dev/null || true"
    cd ..; pass "$NAME installed to $PREFIX"
}

# ---- Targets ------------------------------------------------------------
check_deps() {
    info "Verifying ocws-equalizer system libraries"
    need_pkg libpulse      "libpulse-dev"
    need_pkg libpulse-simple "libpulse-dev"
    need_pkg fftw3         "libfftw3-dev"
    need_pkg cairo         "libcairo2-dev"
    local found_mbeq=false
    for p in "$PREFIX"/lib/ladspa/mbeq_1197.so "$PREFIX"/lib64/ladspa/mbeq_1197.so /usr/lib/ladspa/mbeq_1197.so /usr/lib64/ladspa/mbeq_1197.so; do
        if [ -f "$p" ]; then found_mbeq=true; break; fi
    done
    if [ "$found_mbeq" = "true" ]; then
        pass "mbeq LADSPA plugin present"
    else
        warn "mbeq LADSPA plugin missing — building swh-plugins"
        build_swh_plugins
    fi
}

build_swh_plugins() {
    info "Building swh-plugins (provides mbeq 15-band EQ engine)"
    need_pkg ladspa "ladspa-sdk"
    build_make "swh-plugins" "https://github.com/swh/ladspa-plugins.git"
    pass "swh-plugins built — mbeq_1197.so available for the PipeWire filter-chain"
}

build_cava() {
    info "Building cava (optional alternate visualizer source)"
    need_pkg fftw3 "libfftw3-dev"
    build_make "cava" "https://github.com/karlstav/cava.git"
}

build_easyeffects() {
    info "Building EasyEffects (full GUI preset backend — heavy)"
    warn "EasyEffects pulls lilv, lv2, boost, calf, etc. This is a large build."
    install_pkgs "libgtk-4-dev libadwaita-1-dev liblilv-dev lv2-dev libpipewire-0.3-dev libboost-dev"
    build_make "easyeffects" "https://gitlab.com/wwmm/easyeffects.git"
}

case "${1:-all}" in
    deps)        check_deps ;;
    swh-plugins) build_swh_plugins ;;
    cava)        build_cava ;;
    easyeffects) build_easyeffects ;;
    all)         check_deps; build_swh_plugins ;;
    *) fail "Unknown target: $1. Available: deps, swh-plugins, cava, easyeffects, all" ;;
esac

info "OCWS Audio Build Complete!"
echo -e "${YELLOW}Note:${NC} ocws-equalizer applies EQ via the mbeq PipeWire filter-chain (ocws-eq-apply),"
echo -e "      not EasyEffects. Run 'build-ocws-audio.sh easyeffects' only if you want the full backend."
