#!/bin/sh
# Build FLTK and the fltk-panel prototype
# Usage: ./build-fltk-panel.sh [install]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FLTK_DIR="$PROJECT_DIR/sources/fltk"
FLTK_BUILD="$FLTK_DIR/build"

# Step 1: Build FLTK if not already built
if [ ! -f "$FLTK_BUILD/fltk-config" ]; then
  echo "==> Building FLTK 1.4 (Wayland)..."
  mkdir -p "$FLTK_BUILD"
  cmake -B "$FLTK_BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DOPTION_USE_WAYLAND=ON \
    -DOPTION_USE_X11=OFF \
    -DBUILD_SHARED_LIBS=ON \
    "$FLTK_DIR"
  cmake --build "$FLTK_BUILD" -j"$(nproc)"
  echo "==> FLTK built OK"
fi

# Step 2: Build fltk-panel + fltk-dock
echo "==> Building fltk-panel + fltk-dock..."
make -C "$SCRIPT_DIR" clean all
echo "==> fltk-panel + fltk-dock built OK"

echo ""
echo "Binaries:"
echo "  Top bar:  $SCRIPT_DIR/fltk-panel"
echo "  Dock:     $SCRIPT_DIR/fltk-dock"
echo ""
echo "Run both:  ./fltk-panel & ./fltk-dock &"
echo ""
echo "To install: ./build-fltk-panel.sh install"

# Step 3: Optional install
if [ "${1:-}" = "install" ]; then
  install -Dm755 "$SCRIPT_DIR/fltk-cpp-shell" "$HOME/.local/bin/fltk-cpp-shell"
  echo "==> Installed to ~/.local/bin/fltk-cpp-shell"
  echo ""
  echo "To use as labwc shell mode:"
  echo "  echo fltk-panel > ~/.config/ocws/mode"
  echo ""
  echo "Manually start from autostart:"
  echo "  fltk-cpp-shell &"
fi
