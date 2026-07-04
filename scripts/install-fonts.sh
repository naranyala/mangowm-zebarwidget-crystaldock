#!/bin/bash
#
# install-fonts.sh — Install required fonts for labwc desktop
#
# Installs: Noto Sans, Noto Sans Mono, Inter, Liberation fonts
# These are the base fonts referenced by GTK3/GTK4/Qt configs.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FONTS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
info()  { echo -e "  ${CYAN}→${NC} $1"; }

echo ""
echo -e "${BOLD}Installing Required Fonts${NC}"
echo ""

mkdir -p "$FONTS_DIR"

# --- Check if Noto Sans is already installed system-wide ---
check_system_font() {
  local font_name="$1"
  if fc-list | grep -qi "$font_name"; then
    return 0
  fi
  return 1
}

# --- Download font ---
download_font() {
  local name="$1" url="$2" dest_dir="$3"
  local filename
  filename=$(basename "$url")

  if [[ -f "$dest_dir/$filename" ]]; then
    info "Already downloaded: $filename"
    return 0
  fi

  info "Downloading: $filename"
  if command -v curl &>/dev/null; then
    curl -fLsS -o "$dest_dir/$filename" "$url" 2>/dev/null
  elif command -v wget &>/dev/null; then
    wget -q -O "$dest_dir/$filename" "$url" 2>/dev/null
  else
    fail "Need curl or wget"
  fi
}

# --- Extract font archive ---
extract_font() {
  local archive="$1" dest="$2"
  mkdir -p "$dest"
  case "$archive" in
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$dest" 2>/dev/null ;;
    *.tar.xz)       tar -xf "$archive" -C "$dest" 2>/dev/null ;;
    *.zip)          unzip -qo "$archive" -d "$dest" 2>/dev/null ;;
    *.ttf|*.otf)    cp "$archive" "$dest/" ;;
    *)              warn "Unknown format: $archive"; return 1 ;;
  esac
}

# ============================================================
# 1. Noto Sans (UI font)
# ============================================================
echo -e "${BOLD}[1/4] Noto Sans${NC}"

if check_system_font "Noto Sans"; then
  pass "Noto Sans: installed system-wide"
else
  info "Noto Sans not found — installing to $FONTS_DIR"
  NOTO_DIR="$FONTS_DIR/noto-sans"
  mkdir -p "$NOTO_DIR"

  # Download Noto Sans TTF (regular + bold)
  NOTO_URL="https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSans/NotoSans%5Bwdth%2Cwght%5D.ttf"
  download_font "NotoSans" "$NOTO_URL" "$NOTO_DIR"
  pass "Noto Sans installed"
fi

# ============================================================
# 2. Noto Sans Mono (monospace font)
# ============================================================
echo -e "${BOLD}[2/4] Noto Sans Mono${NC}"

if check_system_font "Noto Sans Mono"; then
  pass "Noto Sans Mono: installed system-wide"
else
  info "Noto Sans Mono not found — installing to $FONTS_DIR"
  NOTO_MONO_DIR="$FONTS_DIR/noto-sans-mono"
  mkdir -p "$NOTO_MONO_DIR"

  NOTO_MONO_URL="https://github.com/googlefonts/noto-fonts/raw/main/hinted/ttf/NotoSansMono/NotoSansMono%5Bwdth%2Cwght%5D.ttf"
  download_font "NotoSansMono" "$NOTO_MONO_URL" "$NOTO_MONO_DIR"
  pass "Noto Sans Mono installed"
fi

# ============================================================
# 3. Inter (UI alternative)
# ============================================================
echo -e "${BOLD}[3/4] Inter${NC}"

if check_system_font "Inter"; then
  pass "Inter: installed system-wide"
else
  info "Inter not found — installing to $FONTS_DIR"
  INTER_DIR="$FONTS_DIR/inter"
  mkdir -p "$INTER_DIR"

  INTER_URL="https://github.com/rsms/inter/releases/download/v4.0/Inter-4.0.zip"
  INTER_ZIP="/tmp/inter-font.zip"
  download_font "Inter" "$INTER_URL" "/tmp"
  extract_font "$INTER_ZIP" "$INTER_DIR"
  rm -f "$INTER_ZIP"
  pass "Inter installed"
fi

# ============================================================
# 4. Liberation Fonts (fallback)
# ============================================================
echo -e "${BOLD}[4/4] Liberation Fonts${NC}"

if check_system_font "Liberation Sans"; then
  pass "Liberation: installed system-wide"
else
  warn "Liberation fonts not found — install via package manager:"
  echo -e "    ${DIM}Debian/Ubuntu: sudo apt install fonts-liberation${NC}"
  echo -e "    ${DIM}Fedora: sudo dnf install liberation-sans-fonts${NC}"
  echo -e "    ${DIM}Arch: sudo pacman -S ttf-liberation${NC}"
fi

# ============================================================
# Rebuild font cache
# ============================================================
echo ""
info "Rebuilding font cache..."
if command -v fc-cache &>/dev/null; then
  fc-cache -fv >/dev/null 2>&1 && pass "Font cache rebuilt" || warn "Font cache rebuild failed"
else
  warn "fc-cache not found — install fontconfig"
fi

echo ""
echo -e "${GREEN}${BOLD}Font installation complete!${NC}"
echo ""
echo "Installed fonts:"
fc-list | grep -i "noto sans\|inter\|liberation" | head -10 || true
echo ""
