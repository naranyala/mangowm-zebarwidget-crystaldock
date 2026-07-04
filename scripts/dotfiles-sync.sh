#!/bin/bash
#
# dotfiles-sync.sh — Two-way sync between project dotfiles and ~/.config/labwc
#
# Compare, diff, and sync in either direction.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$PROJECT_DIR/dotfiles/labwc"
DST_DIR="${HOME}/.config/labwc"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
info()  { echo -e "  ${CYAN}→${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
section() { echo -e "\n${BOLD}[$1]${NC}"; }

DIRECTION="diff"
FILES=()

while [[ $# -gt 0 ]]; do
  case $1 in
    diff|push|pull) DIRECTION="$1"; shift ;;
    --all|all) FILES=("rc.xml" "autostart" "environment" "menu.xml" "themerc-override"); shift ;;
    -f|--file) FILES+=("$2"); shift 2 ;;
    --help)
      echo "Usage: $0 <diff|push|pull> [--all|-f FILE]"
      echo ""
      echo "Commands:"
      echo "  diff              Show differences (default)"
      echo "  push              Copy project dotfiles → ~/.config/labwc"
      echo "  pull              Copy ~/.config/labwc → project dotfiles"
      echo ""
      echo "Options:"
      echo "  --all             Operate on all config files"
      echo "  -f, --file FILE   Operate on a specific file"
      echo ""
      echo "Examples:"
      echo "  $0 diff --all"
      echo "  $0 push -f rc.xml"
      echo "  $0 pull -f autostart"
      exit 0
      ;;
    *) shift ;;
  esac
done

CFG_FILES=("rc.xml" "autostart" "environment" "menu.xml" "themerc-override")
if [ ${#FILES[@]} -gt 0 ]; then
  CFG_FILES=("${FILES[@]}")
fi

echo ""
echo "== Dotfiles Sync ($DIRECTION) =="
echo ""

# Ensure target dir exists
[ "$DIRECTION" = "push" ] && mkdir -p "$DST_DIR"

HAS_DIFF=false

for cfg in "${CFG_FILES[@]}"; do
  src="$SRC_DIR/$cfg"
  dst="$DST_DIR/$cfg"

  # Validate rc.xml source before push
  if [ "$DIRECTION" = "push" ] && [ "$cfg" = "rc.xml" ] && [ -f "$src" ]; then
    CLIENT_CTX=$(sed -n '/<context name="Client">/,/<\/context>/p' "$src")
    if echo "$CLIENT_CTX" | grep -q 'button="Left" action="Press"'; then
      warn "rc.xml: source has broken Client context (Left Press) — skipping"
      continue
    fi
  fi

  case "$DIRECTION" in
    diff)
      if [ ! -f "$src" ] && [ ! -f "$dst" ]; then
        info "$cfg: neither source nor target exist"
      elif [ ! -f "$src" ]; then
        warn "$cfg: exists in ~/.config only (not in project)"
      elif [ ! -f "$dst" ]; then
        warn "$cfg: exists in project only (not in ~/.config)"
      elif cmp -s "$src" "$dst"; then
        pass "$cfg: identical"
      else
        HAS_DIFF=true
        echo -e "  ${YELLOW}── $cfg ──${NC}"
        diff --color=always -u "$dst" "$src" 2>/dev/null | tail -n +3 | sed 's/^/    /' || diff -u "$dst" "$src" | tail -n +3 | sed 's/^/    /'
        echo ""
      fi
      ;;

    push)
      if [ ! -f "$src" ]; then
        warn "Source not found: $src"
      elif [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        pass "$cfg: already up to date"
      else
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        pass "$cfg: pushed → $dst"
      fi
      chmod +x "$dst" 2>/dev/null || true
      ;;

    pull)
      if [ ! -f "$dst" ]; then
        warn "Target not found: $dst"
      elif [ -f "$src" ] && cmp -s "$dst" "$src"; then
        pass "$cfg: already up to date"
      else
        mkdir -p "$(dirname "$src")"
        cp "$dst" "$src"
        pass "$cfg: pulled → $src"
      fi
      ;;
  esac
done

if [ "$DIRECTION" = "push" ] || [ "$DIRECTION" = "pull" ]; then
  echo ""
  info "Reload labwc with: labwc --reconfigure"
fi

if [ "$DIRECTION" = "diff" ] && ! $HAS_DIFF; then
  echo ""
  pass "All files in sync"
fi
echo ""
