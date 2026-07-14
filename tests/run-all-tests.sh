#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

pass() { echo -e "\n${GREEN}✓ PASS${NC}: $1"; }
fail() { echo -e "\n${RED}✗ FAIL${NC}: $1"; exit 1; }

echo -e "${BOLD}Running All Project Tests...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "----------------------------------------"
if "$SCRIPT_DIR/run-bash-tests.sh"; then
    pass "Bash Scripts Suite"
else
    fail "Bash Scripts Suite"
fi
echo "----------------------------------------"
if "$SCRIPT_DIR/run-integration-tests.sh"; then
    pass "C Binaries Integration Suite"
else
    fail "C Binaries Integration Suite"
fi
echo "----------------------------------------"
if "$SCRIPT_DIR/run-fltk-panel-tests.sh"; then
    pass "FLTK Panel Suite"
else
    fail "FLTK Panel Suite"
fi
echo "----------------------------------------"

# Run zig build test
if (cd "$SCRIPT_DIR/.." && zig build test); then
    pass "Zig Unit Tests"
else
    fail "Zig Unit Tests"
fi

echo -e "\n${BOLD}🎉 All tests passed successfully!${NC}"
