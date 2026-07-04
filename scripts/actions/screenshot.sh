#!/bin/bash
#
# screenshot.sh — Screenshot with annotation
#
# Modes: full, area, window, timer, annotate
# Tools: grim+slurp, flameshot, ksnip, swappy, satty

set -euo pipefail

MODE="${1:-area}"
DELAY="${2:-0}"
SAVE_DIR="${HOME}/Pictures/screenshots"
CLIPBOARD=true

mkdir -p "$SAVE_DIR"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

FILENAME="screenshot-$(date +%Y%m%d-%H%M%S).png"
FILEPATH="$SAVE_DIR/$FILENAME"

take_screenshot() {
  if command -v grim &>/dev/null && command -v slurp &>/dev/null; then
    case "$MODE" in
      full)
        grim "$FILEPATH"
        ;;
      area)
        grim -g "$(slurp)" "$FILEPATH"
        ;;
      window)
        grim -g "$(slurp -w)" "$FILEPATH"
        ;;
      timer)
        sleep "$DELAY"
        grim "$FILEPATH"
        ;;
      annotate)
        # Pipe area selection directly to annotation tool
        if command -v satty &>/dev/null; then
          grim -g "$(slurp)" - | satty - --save-file "$FILEPATH" --copy-to-clipboard
          return
        elif command -v swappy &>/dev/null; then
          grim -g "$(slurp)" - | swappy -f - -o "$FILEPATH"
          return
        else
          grim -g "$(slurp)" "$FILEPATH"
        fi
        ;;
      annotate-full)
        # Full desktop → annotation tool
        if command -v satty &>/dev/null; then
          grim - | satty - --save-file "$FILEPATH" --copy-to-clipboard
          return
        elif command -v swappy &>/dev/null; then
          grim - | swappy -f - -o "$FILEPATH"
          return
        else
          grim "$FILEPATH"
        fi
        ;;
    esac
  elif command -v flameshot &>/dev/null; then
    case "$MODE" in
      full) flameshot full -p "$SAVE_DIR" ;;
      area|window|annotate) flameshot gui -p "$SAVE_DIR" ;;
      timer) flameshot full -d "$((DELAY * 1000))" -p "$SAVE_DIR" ;;
    esac
  elif command -v ksnip &>/dev/null; then
    case "$MODE" in
      full) ksnip -f "$FILEPATH" ;;
      area|annotate) ksnip -r ;;
      window) ksnip -a ;;
      timer) sleep "$DELAY" && ksnip -f "$FILEPATH" ;;
    esac
  else
    fail "No screenshot tool found. Install grim+slurp, flameshot, or ksnip"
  fi
}

take_screenshot

# Copy to clipboard (if file was created)
if $CLIPBOARD && [ -f "$FILEPATH" ]; then
  if command -v wl-copy &>/dev/null; then
    wl-copy < "$FILEPATH"
  elif command -v xclip &>/dev/null; then
    xclip -selection clipboard -t image/png < "$FILEPATH"
  fi
  pass "Copied to clipboard"
fi

if [ -f "$FILEPATH" ]; then
  pass "Saved: $FILEPATH"
fi
