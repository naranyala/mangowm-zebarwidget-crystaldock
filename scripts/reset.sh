#!/bin/bash
#
# reset.sh — Full dotfiles reset with default options (non-interactive)
#
# Safety: backs up BEFORE changes, validates source, rolls back on failure.
#
# Usage:
#   reset.sh                     Full reset (prompts, backup, relaunch)
#   reset.sh --yes               Skip confirmation prompt
#   reset.sh --no-backup         Skip backup
#   reset.sh --no-relaunch       Skip relaunch
#   reset.sh --restore BACKUP_DIR  Restore from a backup
#   reset.sh --dry-run           Show what would happen without doing it

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
info()  { echo -e "  ${CYAN}→${NC} $1"; }
section() { echo -e "\n${BOLD}[$1]${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find project dir
PROJECT_DIR=""
if [[ -f "$SCRIPT_DIR/../dotfiles/install.sh" ]]; then
  PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
elif [[ -f "$SCRIPT_DIR/../../dotfiles/install.sh" ]]; then
  PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
elif [[ -f "/media/naranyala/Data/projects-remote/labwc-crystaldock-barandwidgets/dotfiles/install.sh" ]]; then
  PROJECT_DIR="/media/naranyala/Data/projects-remote/labwc-crystaldock-barandwidgets"
elif [[ -f "$HOME/projects/labwc-crystaldock-barandwidgets/dotfiles/install.sh" ]]; then
  PROJECT_DIR="$HOME/projects/labwc-crystaldock-barandwidgets"
fi

if [[ -z "$PROJECT_DIR" ]]; then
  fail "Cannot find project directory. Set PROJECT_DIR env or run from project/scripts/"
fi

# --- Parse args ---
YES=false
NO_BACKUP=false
NO_RELAUNCH=false
DRY_RUN=false
RESTORE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)       YES=true; shift ;;
    --no-backup)    NO_BACKUP=true; shift ;;
    --no-relaunch)  NO_RELAUNCH=true; shift ;;
    --dry-run)      DRY_RUN=true; shift ;;
    --restore)
      RESTORE_DIR="${2:-}"
      [[ -z "$RESTORE_DIR" ]] && fail "--restore requires a backup directory path"
      shift 2
      ;;
    --help|-h)
      cat << 'EOF'
Usage: reset.sh [OPTIONS]

Options:
  -y, --yes           Skip confirmation prompt
  --no-backup         Skip backing up current configs
  --no-relaunch       Skip relaunching sfwbar + crystal-dock
  --dry-run           Show what would happen without doing it
  --restore DIR       Restore configs from a backup directory
  -h, --help          Show this help

Examples:
  reset.sh                        # Full reset with confirmation
  reset.sh --yes                  # Full reset, no prompt
  reset.sh --restore ~/.config/labwc-backup-20260704-0730
EOF
      exit 0
      ;;
    *) fail "Unknown option: $1 (use --help)" ;;
  esac
done

# --- Restore mode ---
if [[ -n "$RESTORE_DIR" ]]; then
  echo ""
  echo -e "${BOLD}== Restore from Backup ==${NC}"
  if [[ ! -d "$RESTORE_DIR" ]]; then
    fail "Backup directory not found: $RESTORE_DIR"
  fi
  info "Restoring from: $RESTORE_DIR"
  RESTORE_COUNT=0
  for f in "$RESTORE_DIR/labwc"/*; do
    [[ -f "$f" ]] || continue
    name=$(basename "$f")
    cp "$f" "$HOME/.config/labwc/$name"
    pass "Restored $name"
    RESTORE_COUNT=$((RESTORE_COUNT + 1))
  done
  for f in "$RESTORE_DIR/sfwbar"/*; do
    [[ -f "$f" ]] || continue
    name=$(basename "$f")
    cp "$f" "$HOME/.config/sfwbar/$name"
    pass "Restored $name"
    RESTORE_COUNT=$((RESTORE_COUNT + 1))
  done
  if [[ "$RESTORE_COUNT" -eq 0 ]]; then
    warn "No files found in backup to restore"
  fi
  info "Relaunch to apply: relaunch-status-bars.sh"
  exit 0
fi

echo ""
echo -e "${BOLD}== labwc Dotfiles Reset ==${NC}"
echo -e "${DIM}Reinstalls all configs with default options${NC}"
echo ""

# ============================================================
section "1. Pre-flight Checks"
# ============================================================

# Confirm
if [[ "$YES" == "false" && -t 0 ]]; then
  read -rp "This will reset all labwc/sfwbar/crystal-dock configs. Continue? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

# Check labwc
if ! command -v labwc &>/dev/null; then
  fail "labwc not found. Run: ./download-labwc.sh --install"
fi
pass "labwc: $(command -v labwc)"

# Validate source rc.xml BEFORE any changes
SRC_RC="$PROJECT_DIR/dotfiles/labwc/rc.xml"
if [[ -f "$SRC_RC" ]]; then
  # Check XML syntax
  if command -v xmllint &>/dev/null; then
    if xmllint --noout "$SRC_RC" 2>/dev/null; then
      pass "Source rc.xml: valid XML"
    else
      fail "Source rc.xml: INVALID XML — fix before resetting"
    fi
  fi
  # Check Client context
  CLIENT_CTX=$(sed -n '/<context name="Client">/,/<\/context>/p' "$SRC_RC")
  if echo "$CLIENT_CTX" | grep -q 'button="Left" action="Press"'; then
    fail "Source rc.xml: broken Client context (Left Press) — fix before resetting"
  else
    pass "Source rc.xml: Client context OK"
  fi
fi

# Dry run
if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  info "DRY RUN — would perform:"
  echo "  1. Backup: $HOME/.config/labwc-backup-*/"
  echo "  2. Stop: sfwbar, crystal-dock"
  echo "  3. Install: rc.xml, autostart, environment, menu.xml, themerc-override"
  echo "  4. Install: sfwbar.config, catppuccin-mocha.css, *.widget"
  echo "  5. Install: GTK3/GTK4 settings"
  echo "  6. Install: scripts to ~/.local/bin/"
  echo "  7. Validate: XML, Client context, binaries"
  echo "  8. Relaunch: sfwbar + crystal-dock"
  exit 0
fi

# ============================================================
section "2. Backup Current Configs"
# ============================================================

BACKUP_DIR=""
if [[ "$NO_BACKUP" == "false" ]]; then
  BACKUP_DIR="$HOME/.config/labwc-backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR/labwc" "$BACKUP_DIR/sfwbar" "$BACKUP_DIR/crystal-dock"

  BACKUP_COUNT=0
  for cfg in rc.xml autostart environment menu.xml themerc-override; do
    if [[ -f "$HOME/.config/labwc/$cfg" ]]; then
      cp "$HOME/.config/labwc/$cfg" "$BACKUP_DIR/labwc/"
      pass "labwc/$cfg"
      BACKUP_COUNT=$((BACKUP_COUNT + 1))
    fi
  done
  for cfg in sfwbar.config catppuccin-mocha.css; do
    if [[ -f "$HOME/.config/sfwbar/$cfg" ]]; then
      cp "$HOME/.config/sfwbar/$cfg" "$BACKUP_DIR/sfwbar/"
      pass "sfwbar/$cfg"
      BACKUP_COUNT=$((BACKUP_COUNT + 1))
    fi
  done
  # Copy widget files
  for f in "$HOME/.config/sfwbar"/*.widget; do
    [[ -f "$f" ]] || continue
    cp "$f" "$BACKUP_DIR/sfwbar/"
    pass "sfwbar/$(basename "$f")"
    BACKUP_COUNT=$((BACKUP_COUNT + 1))
  done

  if [[ -d "$HOME/.config/crystal-dock" ]]; then
    cp -r "$HOME/.config/crystal-dock/"* "$BACKUP_DIR/crystal-dock/" 2>/dev/null || true
    pass "crystal-dock/ (backed up)"
    BACKUP_COUNT=$((BACKUP_COUNT + 1))
  fi

  if [[ "$BACKUP_COUNT" -eq 0 ]]; then
    warn "No existing configs found to backup"
    rmdir "$BACKUP_DIR/labwc" "$BACKUP_DIR/sfwbar" "$BACKUP_DIR" 2>/dev/null || true
    BACKUP_DIR=""
  else
    pass "Backup saved: $BACKUP_DIR ($BACKUP_COUNT files)"
  fi
else
  info "Skipping backup (--no-backup)"
fi

# ============================================================
section "3. Stop Running Processes"
# ============================================================

STOPPED=0
if pgrep -x sfwbar &>/dev/null; then
  pkill -9 -x sfwbar 2>/dev/null || true
  STOPPED=$((STOPPED + 1))
fi
if pgrep -x crystal-dock &>/dev/null; then
  pkill -9 -x crystal-dock 2>/dev/null || true
  STOPPED=$((STOPPED + 1))
fi

if [[ "$STOPPED" -gt 0 ]]; then
  sleep 0.5
  pass "Stopped $STOPPED process(es)"
else
  info "No processes to stop"
fi

# ============================================================
section "4. Install Default Configs"
# ============================================================

INSTALL_LOG=$(mktemp)
trap 'rm -f "$INSTALL_LOG"' EXIT

# Enforce default crystal-dock configuration by wiping user modifications
rm -rf "$HOME/.config/crystal-dock"

if [[ -f "$PROJECT_DIR/dotfiles/install.sh" ]]; then
  if bash "$PROJECT_DIR/dotfiles/install.sh" > "$INSTALL_LOG" 2>&1; then
    pass "Dotfiles installed"
  else
    warn "install.sh had errors — check $INSTALL_LOG"
    # Rollback if backup exists
    if [[ -n "$BACKUP_DIR" ]]; then
      warn "Rolling back from backup..."
      for f in "$BACKUP_DIR/labwc"/*; do
        [[ -f "$f" ]] && cp "$f" "$HOME/.config/labwc/" 2>/dev/null || true
      done
      for f in "$BACKUP_DIR/sfwbar"/*; do
        [[ -f "$f" ]] && cp "$f" "$HOME/.config/sfwbar/" 2>/dev/null || true
      done
      pass "Rolled back from backup"
    fi
    fail "Install failed. Check: $INSTALL_LOG"
  fi
else
  fail "install.sh not found: $PROJECT_DIR/dotfiles/install.sh"
fi

# ============================================================
section "5. Validate Setup"
# ============================================================

VALIDATE_ERRORS=0
if [[ -f "$PROJECT_DIR/scripts/validate.sh" ]]; then
  if bash "$PROJECT_DIR/scripts/validate.sh" > "$INSTALL_LOG" 2>&1; then
    pass "Validation passed"
  else
    VALIDATE_ERRORS=$(grep -c "✗" "$INSTALL_LOG" 2>/dev/null | head -1 || echo "0")
    VALIDATE_ERRORS="${VALIDATE_ERRORS//[^0-9]/}"
    [[ -z "$VALIDATE_ERRORS" ]] && VALIDATE_ERRORS=0
    if [[ "$VALIDATE_ERRORS" -gt 0 ]]; then
      warn "Validation found $VALIDATE_ERRORS issue(s)"
      grep "✗" "$INSTALL_LOG" 2>/dev/null | head -5 | sed 's/^/    /' || true
    else
      pass "Validation passed (warnings only)"
    fi
  fi
else
  warn "validate.sh not found"
fi

# ============================================================
section "6. Relaunch Services"
# ============================================================

if [[ "$NO_RELAUNCH" == "false" ]]; then
  if command -v relaunch-status-bars.sh &>/dev/null; then
    if relaunch-status-bars.sh all > "$INSTALL_LOG" 2>&1; then
      pass "sfwbar + crystal-dock relaunched"
    else
      warn "Relaunch had issues"
    fi
  else
    warn "relaunch-status-bars.sh not found"
  fi
else
  info "Skipping relaunch (--no-relaunch)"
fi

# ============================================================
section "Summary"
# ============================================================

echo ""
if [[ "$VALIDATE_ERRORS" -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}Reset Complete!${NC}"
else
  echo -e "${YELLOW}${BOLD}Reset Complete (with $VALIDATE_ERRORS warning(s))${NC}"
fi
echo ""
echo "Restored:"
echo "  • labwc config      → ~/.config/labwc/"
echo "  • SFWBar config     → ~/.config/sfwbar/"
echo "  • Scripts           → ~/.local/bin/"
echo ""
if [[ -n "$BACKUP_DIR" ]]; then
  echo "Backup: $BACKUP_DIR"
  echo "Restore: reset.sh --restore $BACKUP_DIR"
fi
echo ""
