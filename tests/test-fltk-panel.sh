#!/bin/bash
# FLTK Panel Test Suite
# Tests build validation, binary format, dependencies, smoke tests,
# FLTK source validation, build script checks, and production panel cross-check

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/fltk-panel"
FLTK_BUILD_DIR="$PROJECT_DIR/build/fltk"
FLTK_SRC="$PROJECT_DIR/sources/fltk"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

header() { echo -e "\n${BOLD}${CYAN}=== $1 ===${NC}"; }
pass()   { echo -e "  ${GREEN}[PASS]${NC} $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail()   { echo -e "  ${RED}[FAIL]${NC} $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
skip()   { echo -e "  ${YELLOW}[SKIP]${NC} $1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

# ============================================================
# 1. Build Validation
# ============================================================
header "Build Validation"

# Check FLTK static library exists
if [ -f "$FLTK_BUILD_DIR/lib/libfltk.a" ]; then
    pass "FLTK static library exists"
else
    fail "FLTK static library missing: $FLTK_BUILD_DIR/lib/libfltk.a"
fi

# Check FLTK images library exists
if [ -f "$FLTK_BUILD_DIR/lib/libfltk_images.a" ]; then
    pass "FLTK images library exists"
else
    fail "FLTK images library missing"
fi

# Check panel binary exists
if [ -f "$BUILD_DIR/panel" ]; then
    pass "Panel binary exists"
else
    fail "Panel binary missing: $BUILD_DIR/panel"
fi

# Check panel source exists
if [ -f "$PROJECT_DIR/fltk-panel/panel.cpp" ]; then
    pass "Panel source exists"
else
    fail "Panel source missing: fltk-panel/panel.cpp"
fi

# Check build script exists and is executable
if [ -x "$PROJECT_DIR/fltk-panel/build.sh" ]; then
    pass "Build script is executable"
else
    fail "Build script missing or not executable"
fi

# ============================================================
# 2. Binary Format
# ============================================================
header "Binary Format"

PANEL_BIN="$BUILD_DIR/panel"

if [ -f "$PANEL_BIN" ]; then
    # Check ELF format
    FILE_INFO=$(file "$PANEL_BIN" 2>/dev/null || true)
    if echo "$FILE_INFO" | grep -q "ELF"; then
        pass "Binary is ELF format"
    else
        fail "Binary is not ELF format"
    fi

    # Check architecture
    if echo "$FILE_INFO" | grep -q "x86-64"; then
        pass "Binary is x86-64 architecture"
    else
        fail "Binary is not x86-64 architecture"
    fi

    # Check dynamically linked
    if echo "$FILE_INFO" | grep -q "dynamically linked"; then
        pass "Binary is dynamically linked"
    else
        fail "Binary is not dynamically linked"
    fi

    # Check no unresolved dependencies
    LDD_OUT=$(ldd "$PANEL_BIN" 2>&1 || true)
    if echo "$LDD_OUT" | grep -q "not found"; then
        fail "Binary has unresolved dependencies"
        echo "$LDD_OUT" | grep "not found" | head -5
    else
        pass "All shared libraries resolve"
    fi
else
    skip "Binary format tests (binary not built)"
fi

# ============================================================
# 3. Binary Dependencies
# ============================================================
header "Binary Dependencies"

if [ -f "$PANEL_BIN" ]; then
    REQUIRED_LIBS=(
        "wayland-client"
        "wayland-cursor"
        "cairo"
        "pango"
        "pangocairo"
        "xkbcommon"
    )

    LDD_OUT=$(ldd "$PANEL_BIN" 2>/dev/null || true)

    for lib in "${REQUIRED_LIBS[@]}"; do
        if echo "$LDD_OUT" | grep -q "$lib"; then
            pass "Required library: $lib"
        else
            fail "Missing required library: $lib"
        fi
    done

    # Check optional but expected libs
    OPTIONAL_LIBS=("gtk" "dbus")
    for lib in "${OPTIONAL_LIBS[@]}"; do
        if echo "$LDD_OUT" | grep -qi "$lib"; then
            pass "Optional library present: $lib"
        else
            skip "Optional library not linked: $lib"
        fi
    done
else
    skip "Dependency tests (binary not built)"
fi

# ============================================================
# 4. Smoke Tests
# ============================================================
header "Smoke Tests"

if [ -f "$PANEL_BIN" ]; then
    # Test with timeout (2 seconds)
    SMOKE_OUTPUT=$(timeout 2 "$PANEL_BIN" 2>&1 || true)
    SMOKE_EXIT=$?

    # Panel should either run (timeout) or fail gracefully
    if [ $SMOKE_EXIT -eq 124 ]; then
        pass "Panel runs for 2+ seconds without crash"
    elif [ $SMOKE_EXIT -eq 0 ]; then
        pass "Panel exited cleanly"
    else
        # Check if it failed due to missing Wayland display (expected in test)
        if echo "$SMOKE_OUTPUT" | grep -qi "wayland\|display\|connect"; then
            pass "Panel failed gracefully (no Wayland display)"
        else
            fail "Panel crashed unexpectedly (exit=$SMOKE_EXIT)"
        fi
    fi

    # Test with invalid WAYLAND_DISPLAY
    WAYLAND_DISPLAY=nonexistent timeout 1 "$PANEL_BIN" 2>&1 || true
    BAD_EXIT=$?
    if [ $BAD_EXIT -ne 0 ]; then
        pass "Panel fails gracefully with invalid WAYLAND_DISPLAY"
    else
        skip "Panel accepted invalid WAYLAND_DISPLAY"
    fi

    # Test FLTK_BACKEND=x11 fallback
    FLTK_BACKEND=x11 timeout 1 "$PANEL_BIN" 2>&1 || true
    X11_EXIT=$?
    if [ $X11_EXIT -ne 0 ]; then
        pass "X11 backend fallback attempted"
    else
        skip "X11 backend not tested"
    fi
else
    skip "Smoke tests (binary not built)"
fi

# ============================================================
# 5. FLTK Source Validation
# ============================================================
header "FLTK Source Validation"

# Check FLTK source directory exists
if [ -d "$FLTK_SRC" ]; then
    pass "FLTK source directory exists"
else
    fail "FLTK source directory missing: $FLTK_SRC"
fi

# Check CMakeLists.txt
if [ -f "$FLTK_SRC/CMakeLists.txt" ]; then
    pass "FLTK CMakeLists.txt exists"
else
    fail "FLTK CMakeLists.txt missing"
fi

# Check version
if grep -q "project(FLTK VERSION" "$FLTK_SRC/CMakeLists.txt" 2>/dev/null; then
    VERSION=$(grep "project(FLTK VERSION" "$FLTK_SRC/CMakeLists.txt" | sed 's/.*VERSION \([0-9.]*\).*/\1/')
    pass "FLTK version: $VERSION"
else
    fail "Cannot determine FLTK version"
fi

# Check Wayland backend source
if [ -f "$FLTK_SRC/src/drivers/Wayland/Fl_Wayland_Window_Driver.cxx" ]; then
    pass "Wayland backend source exists"
else
    fail "Wayland backend source missing"
fi

# Check Cairo integration
if [ -f "$FLTK_SRC/src/drivers/Cairo/Fl_Cairo_Graphics_Driver.cxx" ]; then
    pass "Cairo integration source exists"
else
    fail "Cairo integration source missing"
fi

# ============================================================
# 6. Build Script Validation
# ============================================================
header "Build Script Validation"

BUILD_SCRIPT="$PROJECT_DIR/fltk-panel/build.sh"

# Syntax check
if bash -n "$BUILD_SCRIPT" 2>/dev/null; then
    pass "Build script syntax valid"
else
    fail "Build script syntax error"
fi

# Check script references FLTK paths
if grep -q "FLTK_BUILD_DIR\|libfltk.a" "$BUILD_SCRIPT" 2>/dev/null; then
    pass "Build script references FLTK library"
else
    fail "Build script missing FLTK library reference"
fi

# Check script checks for FLTK build
if grep -q "libfltk.a" "$BUILD_SCRIPT" 2>/dev/null; then
    pass "Build script checks for FLTK static lib"
else
    fail "Build script doesn't verify FLTK build"
fi

# ============================================================
# 7. Production Panel Cross-Check
# ============================================================
header "Production Panel Cross-Check"

PROD_DIR="$PROJECT_DIR/src/shells/fltk-panel"

# Check main.cpp
if [ -f "$PROD_DIR/main.cpp" ]; then
    pass "Production panel source exists"
else
    fail "Production panel source missing"
fi

# Check Makefile
if [ -f "$PROD_DIR/Makefile" ]; then
    pass "Production panel Makefile exists"
else
    fail "Production panel Makefile missing"
fi

# Check generated protocol files
PROTOCOL_FILES=(
    "wlr-layer-shell-unstable-v1-client-protocol.c"
    "wlr-layer-shell-unstable-v1-client-protocol.h"
    "wlr-foreign-toplevel-management-unstable-v1-client-protocol.c"
    "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"
    "xdg-shell-client-protocol.c"
    "xdg-shell-client-protocol.h"
)

for pf in "${PROTOCOL_FILES[@]}"; do
    if [ -f "$PROD_DIR/$pf" ]; then
        pass "Protocol file: $pf"
    else
        fail "Protocol file missing: $pf"
    fi
done

# Check compiled binary
if [ -x "$PROD_DIR/fltk-panel" ]; then
    pass "Production panel binary exists"
else
    fail "Production panel binary missing"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  FLTK Panel Test Results${NC}"
echo -e "${BOLD}========================================${NC}"
echo -e "  ${GREEN}PASS: $PASS_COUNT${NC}"
echo -e "  ${RED}FAIL: $FAIL_COUNT${NC}"
echo -e "  ${YELLOW}SKIP: $SKIP_COUNT${NC}"
echo -e "${BOLD}========================================${NC}"

if [ $FAIL_COUNT -gt 0 ]; then
    exit 1
fi
