#!/bin/bash
# -------------------------------------------------------------------
# OCWS Testing & Validation Suite
# Validates the integrity of the codebase, IPC API, and configurations.
# -------------------------------------------------------------------

set -uo pipefail

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
pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; ((PASS_COUNT++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL_COUNT++)); }
skip() { echo -e "  ${YELLOW}[SKIP]${NC} $1"; ((SKIP_COUNT++)); }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# 1. Syntax Validation (Bash)
# ============================================================
header "Bash Syntax Validation"
sh_files=$(find "$SCRIPT_DIR" -type f -name "*.sh")
if [ -n "$sh_files" ]; then
    for file in $sh_files; do
        if bash -n "$file"; then
            pass "Syntax valid: $(basename "$file")"
        else
            fail "Syntax error in: $(basename "$file")"
        fi
    done
else
    skip "No bash scripts found."
fi

# ============================================================
# 2. XML Integrity (labwc)
# ============================================================
header "XML Integrity (labwc rc.xml)"
RC_XML="$SCRIPT_DIR/dotfiles/labwc/rc.xml"
if [ -f "$RC_XML" ]; then
    if command -v xmllint >/dev/null 2>&1; then
        if xmllint --noout "$RC_XML" 2>/dev/null; then
            pass "rc.xml is perfectly well-formed."
        else
            fail "rc.xml contains invalid XML syntax."
        fi
    else
        skip "xmllint not installed, skipping strict XML validation."
    fi
else
    fail "rc.xml not found!"
fi

# ============================================================
# 3. OCWS Configuration Validation
# ============================================================
header "OCWS UI Engine Validation"
OCWS_CFG="$SCRIPT_DIR/dotfiles/ocws/ocws.config"
if [ -f "$OCWS_CFG" ]; then
    if grep -q 'include("plugins.config")' "$OCWS_CFG"; then
        pass "Plugin autoloader anchor is present."
    else
        fail "Plugin autoloader anchor missing in ocws.config!"
    fi

    if grep -q 'Theme = "Adwaita-dark"' "$OCWS_CFG"; then
        pass "GTK base theme fallback is properly set."
    else
        fail "GTK base theme fallback missing!"
    fi
else
    fail "ocws.config not found!"
fi

# ============================================================
# 4. OCWS Event Bus (IPC) Validation
# ============================================================
header "OCWS Event Bus API Validation"
EMIT_SCRIPT="$SCRIPT_DIR/scripts/ocws-emit.sh"
if [ -f "$EMIT_SCRIPT" ]; then
    NAMESPACES=("System.Volume" "System.Brightness" "System.Cpu" "System.Memory" "Media.Title" "System.DND")
    for ns in "${NAMESPACES[@]}"; do
        if grep -q "\"$ns\")" "$EMIT_SCRIPT"; then
            pass "Namespace mapped correctly: $ns"
        else
            fail "Missing expected IPC namespace: $ns"
        fi
    done
else
    fail "ocws-emit.sh IPC script not found!"
fi

# ============================================================
# 5. Core Environment Dependencies
# ============================================================
header "Core Dependency Health Check"
for cmd in labwc sfwbar fuzzel pipewire wl-clipboard; do
    if command -v "$cmd" >/dev/null 2>&1; then
        pass "Core binary found: $cmd"
    else
        skip "Core binary not found on this system (Test env only): $cmd"
    fi
done

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${BOLD}Test Suite Summary:${NC}"
echo -e "  ${GREEN}Passed:${NC} $PASS_COUNT"
echo -e "  ${YELLOW}Skipped:${NC} $SKIP_COUNT"
echo -e "  ${RED}Failed:${NC} $FAIL_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
