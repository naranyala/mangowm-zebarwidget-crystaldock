#!/bin/bash
#
# relaunch-status-bars.sh — Restart sfwbar and crystal-dock
#
# Usage: relaunch-status-bars.sh [sfwbar|dock|all]
#   No args or "all" → restart both
#   "sfwbar"         → restart sfwbar only
#   "dock"           → restart crystal-dock only

export PATH="$HOME/.local/bin:$PATH"

set -euo pipefail

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
section() { echo -e "\n${BOLD}[$1]${NC}"; }

TARGET="${1:-all}"

# ---- Stop ----
section "Stopping"

stop_statusbar() {
  if pgrep -x sfwbar >/dev/null 2>&1; then
    pkill -9 -x sfwbar
    sleep 0.3
    pass "sfwbar stopped"
  fi
  if pgrep -x noctalia >/dev/null 2>&1; then
    pkill -9 -x noctalia
    sleep 0.3
    pass "noctalia stopped"
  fi
}

stop_dock() {
  if pgrep -x crystal-dock >/dev/null 2>&1; then
    pkill -9 -x crystal-dock
    sleep 0.3
    pass "crystal-dock stopped"
  else
    info "crystal-dock not running"
  fi
}

case "$TARGET" in
  sfwbar|statusbar) stop_statusbar ;;
  dock)   stop_dock ;;
  all)    stop_statusbar; stop_dock ;;
  *)      fail "Unknown target: $TARGET (use statusbar, dock, or all)" ;;
esac

# ---- Start ----
section "Starting"

CSS_FILE="$HOME/.config/sfwbar/theme.css"
CONFIG_FILE="$HOME/.config/sfwbar/sfwbar.config"
CSS_ARG=""
CONFIG_ARG=""
[ -f "$CSS_FILE" ] && CSS_ARG="-c $CSS_FILE"
[ -f "$CONFIG_FILE" ] && CONFIG_ARG="-f $CONFIG_FILE"

start_statusbar() {
  STATUSBAR="sfwbar"
  if [ -f "$HOME/.config/labwc-widgets/status.json" ]; then
    VAL=$(grep -o '"statusbar"[[:space:]]*:[[:space:]]*"[^"]*"' "$HOME/.config/labwc-widgets/status.json" 2>/dev/null | head -1 | sed 's/.*": *"//;s/"$//')
    [ -n "$VAL" ] && STATUSBAR="$VAL"
  fi

  if [ "$STATUSBAR" = "noctalia" ]; then
    if ! command -v noctalia >/dev/null 2>&1; then
      warn "noctalia binary not found, falling back to sfwbar"
      STATUSBAR="sfwbar"
    else
      nohup noctalia > /dev/null 2>&1 &
      sleep 1
      if pgrep -x noctalia >/dev/null 2>&1; then
        pass "noctalia started (PID: $(pgrep -x noctalia))"
      else
        warn "noctalia failed to start, falling back to sfwbar"
        STATUSBAR="sfwbar"
      fi
    fi
  fi

  if [ "$STATUSBAR" = "sfwbar" ]; then
    if ! command -v sfwbar >/dev/null 2>&1; then
      warn "sfwbar binary not found, skipping"
      return
    fi
    nohup sfwbar $CONFIG_ARG $CSS_ARG > /dev/null 2>&1 &
    sleep 1
    if pgrep -x sfwbar >/dev/null 2>&1; then
      pass "sfwbar started (PID: $(pgrep -x sfwbar))"
    else
      warn "sfwbar failed to start"
    fi
  fi
}

start_dock() {
  if ! command -v crystal-dock >/dev/null 2>&1; then
    warn "crystal-dock binary not found, skipping"
    return
  fi
  # Clean up stale Qt shared memory locks from crashes or SIGKILL
  rm -f /tmp/qipc_sharedmemory_crystaldock* /tmp/qipc_systemsem_crystaldock* 2>/dev/null || true
  
  nohup crystal-dock > /dev/null 2>&1 &
  sleep 2
  if pgrep -x crystal-dock >/dev/null 2>&1; then
    pass "crystal-dock started (PID: $(pgrep -x crystal-dock))"
  else
    warn "crystal-dock failed to start"
  fi
}

case "$TARGET" in
  sfwbar|statusbar) start_statusbar ;;
  dock)   start_dock ;;
  all)    start_statusbar; start_dock ;;
esac

section "Status"
pgrep -x sfwbar >/dev/null 2>&1 && pass "sfwbar: running"
pgrep -x noctalia >/dev/null 2>&1 && pass "noctalia: running"
pgrep -x crystal-dock >/dev/null 2>&1 && pass "crystal-dock: running"

