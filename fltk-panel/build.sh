#!/bin/bash
# Build script for FLTK Wayland panel exploration
# Builds the FLTK panel with all Wayland integrations
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$PROJECT_DIR")"
BUILD_DIR="$ROOT_DIR/build/fltk-panel"
FLTK_BUILD_DIR="$ROOT_DIR/build/fltk"
FLTK_SRC="$ROOT_DIR/sources/fltk"

echo "=== FLTK Wayland Panel Build ==="

# Check if FLTK is built
if [ ! -f "$FLTK_BUILD_DIR/lib/libfltk.a" ]; then
    echo "ERROR: FLTK not built. Run build in build/fltk/ first."
    exit 1
fi

# Create build directory
mkdir -p "$BUILD_DIR"

# Get pkg-config flags for ALL FLTK Wayland dependencies
# FLTK Wayland needs: wayland-client, wayland-cursor, wayland-egl,
# xkbcommon, cairo, pango, pangocairo, gtk+-3.0 (libdecor), dbus-1
PKG_CFLAGS="$(pkg-config --cflags \
    cairo pango pangocairo \
    wayland-client wayland-cursor wayland-egl \
    xkbcommon gtk+-3.0 dbus-1 \
    2>/dev/null || true)"
PKG_LIBS="$(pkg-config --libs \
    cairo pango pangocairo \
    wayland-client wayland-cursor wayland-egl \
    xkbcommon gtk+-3.0 dbus-1 \
    2>/dev/null || true)"

# FLTK include paths
FLTK_CFLAGS="-I$FLTK_BUILD_DIR -I$FLTK_SRC -I$FLTK_SRC/FL"

echo "FLTK: $FLTK_BUILD_DIR/lib/libfltk.a"
echo "Deps: $(pkg-config --modversion cairo pango wayland-client gtk+-3.0 2>/dev/null | tr '\n' ' ')"
echo ""

# Compile all C++ sources
CXXFLAGS="-std=c++17 -O2 -Wall -Wextra -Wno-unused-parameter $FLTK_CFLAGS $PKG_CFLAGS"

echo "--- Compiling ---"
for src in "$PROJECT_DIR"/*.cpp; do
    name=$(basename "$src" .cpp)
    # Only build panel and toplevel-dock
    case "$name" in
        simple-panel|wayland-panel) continue ;;
    esac
    echo "  $name.cpp"
    g++ $CXXFLAGS -c "$src" -o "$BUILD_DIR/$name.o"
done

# Protocol code is compiled via toplevel-dock.cpp (includes protocol header)
# No separate C compilation needed

echo ""
echo "--- Linking ---"

# Link order matters: objects first, then FLTK, then system libs
OBJS=$(find "$BUILD_DIR" -name "*.o" -not -path "*/panel.o" 2>/dev/null | sort)
FLTK_LIBS="$FLTK_BUILD_DIR/lib/libfltk_images.a $FLTK_BUILD_DIR/lib/libfltk.a"

echo "  panel -> $BUILD_DIR/panel"
g++ -o "$BUILD_DIR/panel" \
    "$BUILD_DIR/panel.o" \
    $OBJS \
    $FLTK_LIBS \
    $PKG_LIBS \
    -lpthread -ldl -lm

echo ""
echo "=== Build complete ==="
echo "Binary: $BUILD_DIR/panel"
echo ""
echo "To run on Wayland:"
echo "  $BUILD_DIR/panel"
echo ""
echo "To run with XWayland fallback:"
echo "  FLTK_BACKEND=x11 $BUILD_DIR/panel"
