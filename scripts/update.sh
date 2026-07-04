#!/bin/bash
#
# update.sh — Update labwc to latest version from GitHub
#
# Downloads latest source, rebuilds, and optionally updates configs.
# Cleans up after itself — no leftover source files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

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

UPDATE_DOTFILES=false
UPDATE_CONFIG=false
SKIP_BUILD=false
CURRENT_TAG=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --dotfiles) UPDATE_DOTFILES=true; shift ;;
    --config) UPDATE_CONFIG=true; shift ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    --all) UPDATE_DOTFILES=true; UPDATE_CONFIG=true; shift ;;
    --version) CURRENT_TAG="$2"; shift 2 ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --dotfiles     Also update dotfiles from project"
      echo "  --config       Also update ~/.config/labwc from project"
      echo "  --skip-build   Check for update but don't rebuild"
      echo "  --all          Update everything"
      echo "  --version TAG  Target a specific version (default: latest)"
      echo "  --help         Show this help"
      echo ""
      exit 0
      ;;
    *) shift ;;
  esac
done

echo ""
echo "== labwc Updater =="
echo ""

cleanup() { [[ -n "${TMPDIR:-}" && -d "$TMPDIR" ]] && rm -rf "$TMPDIR"; }
trap cleanup EXIT

# -------------------------------------------------------------------
section "1. Checking latest version"
# -------------------------------------------------------------------
REPO="labwc/labwc"
if [ -z "$CURRENT_TAG" ]; then
  info "Fetching latest release from GitHub..."
  CURRENT_TAG=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": "\(.*\)",/\1/')
fi

if [ -z "$CURRENT_TAG" ]; then
  info "No release found, using master"
  CURRENT_TAG="master"
  TARBALL_URL="https://github.com/$REPO/archive/refs/heads/master.tar.gz"
  SHORT_REF="master"
else
  SHORT_REF="$CURRENT_TAG"
  TARBALL_URL="https://github.com/$REPO/archive/refs/tags/$CURRENT_TAG.tar.gz"
fi

info "Target: $SHORT_REF"

# Check current installed version
INSTALLED_VER="$(labwc --version 2>/dev/null || true)"
if [ -n "$INSTALLED_VER" ]; then
  info "Installed: ${INSTALLED_VER%%$'\n'*}"
  if echo "$INSTALLED_VER" | grep -qi "$SHORT_REF"; then
    info "Already at $SHORT_REF"
  fi
fi

if $SKIP_BUILD; then
  pass "Update check complete (--skip-build)"
  exit 0
fi

# -------------------------------------------------------------------
section "2. Downloading source"
# -------------------------------------------------------------------
TMPDIR=$(mktemp -d)
info "Downloading labwc ($SHORT_REF) ..."
curl -sL "$TARBALL_URL" -o "$TMPDIR/labwc.tar.gz"

info "Extracting..."
EXTRACT_DIR=$(tar -tzf "$TMPDIR/labwc.tar.gz" | head -1 | cut -d/ -f1)
tar -xzf "$TMPDIR/labwc.tar.gz" -C "$TMPDIR"
SRC_DIR="$TMPDIR/$EXTRACT_DIR"
pass "Source ready"

# -------------------------------------------------------------------
section "3. Building"
# -------------------------------------------------------------------
info "Building labwc ($SHORT_REF) ..."
cd "$SRC_DIR"
meson setup build/ || fail "meson setup failed"
meson compile -C build/ || fail "meson compile failed"
pass "Build successful"

# -------------------------------------------------------------------
section "4. Installing"
# -------------------------------------------------------------------
info "Installing..."
if meson install --skip-subprojects -C build/ 2>/dev/null; then
  pass "labwc $SHORT_REF installed"
else
  warn "Install failed (may need sudo)"
  info "Run: sudo meson install --skip-subprojects -C $SRC_DIR/build/"
fi

# -------------------------------------------------------------------
# 5. Update dotfiles
# -------------------------------------------------------------------
if $UPDATE_DOTFILES; then
  section "5. Updating dotfiles"
  DOTFILES_DST="${HOME}/.config/labwc"
  DOTFILES_SRC="$PROJECT_DIR/dotfiles/labwc"

  mkdir -p "$DOTFILES_DST"
  UPDATED=0
  for cfg in rc.xml autostart environment menu.xml themerc-override; do
    if [ -f "$DOTFILES_SRC/$cfg" ]; then
      # Validate rc.xml source before updating
      if [ "$cfg" = "rc.xml" ]; then
        CLIENT_CTX=$(sed -n '/<context name="Client">/,/<\/context>/p' "$DOTFILES_SRC/$cfg")
        if echo "$CLIENT_CTX" | grep -q 'button="Left" action="Press"'; then
          warn "rc.xml: source has broken Client context (Left Press) — skipping"
          continue
        fi
      fi
      if [ -f "$DOTFILES_DST/$cfg" ]; then
        if ! cmp -s "$DOTFILES_SRC/$cfg" "$DOTFILES_DST/$cfg" 2>/dev/null; then
          cp "$DOTFILES_SRC/$cfg" "$DOTFILES_DST/$cfg"
          pass "Updated $cfg"
          ((UPDATED++))
        fi
      else
        cp "$DOTFILES_SRC/$cfg" "$DOTFILES_DST/$cfg"
        pass "Installed $cfg"
        ((UPDATED++))
      fi
    fi
  done
  [ "$UPDATED" -gt 0 ] && pass "Updated $UPDATED config file(s)" || info "All up to date"
fi

# -------------------------------------------------------------------
# 6. Update user config from config/
# -------------------------------------------------------------------
if $UPDATE_CONFIG; then
  section "6. Updating user config"
  CONFIG_DST="${HOME}/.config/labwc"
  CONFIG_SRC="$PROJECT_DIR/config/labwc"

  if [ -d "$CONFIG_SRC" ]; then
    UPDATED=0
    for cfg in rc.xml autostart environment menu.xml themerc-override; do
      if [ -f "$CONFIG_SRC/$cfg" ] && [ -f "$CONFIG_DST/$cfg" ]; then
        # Validate rc.xml source before updating
        if [ "$cfg" = "rc.xml" ]; then
          CLIENT_CTX=$(sed -n '/<context name="Client">/,/<\/context>/p' "$CONFIG_SRC/$cfg")
          if echo "$CLIENT_CTX" | grep -q 'button="Left" action="Press"'; then
            warn "rc.xml: config source has broken Client context (Left Press) — skipping"
            continue
          fi
        fi
        if ! cmp -s "$CONFIG_SRC/$cfg" "$CONFIG_DST/$cfg" 2>/dev/null; then
          cp "$CONFIG_SRC/$cfg" "$CONFIG_DST/$cfg"
          pass "Updated $cfg"
          ((UPDATED++))
        fi
      fi
    done
    [ "$UPDATED" -gt 0 ] && pass "Updated $UPDATED config file(s)" || info "All up to date"
  fi
fi

# -------------------------------------------------------------------
# 7. Reload
# -------------------------------------------------------------------
if pgrep -x labwc &>/dev/null; then
  echo ""
  info "Reloading labwc..."
  labwc --reconfigure 2>/dev/null && pass "labwc reloaded" || warn "Could not reload labwc"
fi

echo ""
pass "Update complete: $SHORT_REF"
echo ""
