#!/bin/bash
# autorun-manager — Manage autorun programs at startup
# Config: ~/.config/labwc/autorun.conf

set -euo pipefail

CFG="${AUTORUN_CONF:-$HOME/.config/labwc/autorun.conf}"
LOG="/tmp/ocws-autorun.log"

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

usage() {
    cat <<EOF
${BOLD}autorun-manager${NC} — Manage autorun programs at startup

${BOLD}Usage:${NC}
  $0 <command> [args...]

${BOLD}Commands:${NC}
  list                    List all autorun programs with status
  add <cmd> [--daemon]    Add a program to autorun
  remove <cmd>            Remove a program from autorun
  enable <cmd>            Enable a disabled program (uncomment)
  disable <cmd>           Disable a program (comment out)
  status                  Show status of running autorun programs
  sync                    Sync config to ~/.config/labwc/
  help                    Show this help

${BOLD}Examples:${NC}
  $0 add flameshot --daemon     Add flameshot as daemon
  $0 add contour               Add contour terminal
  $0 remove flameshot           Remove flameshot from autorun
  $0 disable flameshot          Disable (comment out) flameshot
  $0 enable flameshot           Re-enable flameshot
  $0 list                       List all autorun programs
  $0 status                     Check which autorun programs are running

${BOLD}Config Format:${NC}
  command [args...]             Run command at startup
  daemon:command [args...]      Run as daemon (skip if already running)
  #command [args...]            Disabled (commented out)

EOF
    exit 0
}

ensure_config() {
    mkdir -p "$(dirname "$CFG")"
    if [ ! -f "$CFG" ]; then
        cat > "$CFG" <<'CONF'
# Autorun programs — one command per line
# Lines starting with # are comments, empty lines are ignored
# Format: command [args...]
# Use "daemon:" prefix for programs that should only run once (skip if already running)

daemon:dms run
CONF
        info "Created config: $CFG"
    fi
}

cmd_list() {
    ensure_config
    section "Autorun Programs"
    echo ""

    local i=0
    while IFS= read -r line || [ -n "$line" ]; do
        # Store original line for display
        local original="$line"

        # Skip empty lines
        line="$(echo "$line" | sed 's/#.*//' | xargs)"
        [ -z "$line" ] && continue

        i=$((i + 1))

        # Check if disabled (commented out)
        if [[ "$original" =~ ^[[:space:]]*# ]]; then
            echo -e "  ${DIM}$i. [disabled] $line${NC}"
            continue
        fi

        # Check if daemon
        local is_daemon=false
        local cmd="$line"
        if [[ "$line" == daemon:* ]]; then
            is_daemon=true
            cmd="${line#daemon:}"
            cmd="$(echo "$cmd" | xargs)"
        fi

        # Check if running
        local cmd_name
        cmd_name="$(echo "$cmd" | awk '{print $1}')"
        local running=false
        if pgrep -x "$cmd_name" >/dev/null 2>&1; then
            running=true
        fi

        # Format output
        local status_icon
        local status_text
        if [ "$running" = true ]; then
            status_icon="${GREEN}●${NC}"
            status_text="${GREEN}running${NC}"
        else
            status_icon="${RED}○${NC}"
            status_text="${RED}stopped${NC}"
        fi

        local daemon_text=""
        if [ "$is_daemon" = true ]; then
            daemon_text=" ${DIM}[daemon]${NC}"
        fi

        echo -e "  $status_icon $i. $cmd ${DIM}—${NC} $status_text$daemon_text"
    done < "$CFG"

    if [ $i -eq 0 ]; then
        warn "No autorun programs configured"
        echo -e "  ${DIM}Add programs with: $0 add <command>${NC}"
    fi
    echo ""
}

cmd_add() {
    local cmd=""
    local daemon=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --daemon|-d)
                daemon=true
                shift
                ;;
            *)
                cmd="$1"
                shift
                ;;
        esac
    done

    [ -z "$cmd" ] && fail "Usage: $0 add <command> [--daemon]"

    ensure_config

    # Check if already exists
    local prefix=""
    [ "$daemon" = true ] && prefix="daemon:"

    if grep -qE "^(#?)(${prefix})?${cmd}( |$)" "$CFG" 2>/dev/null; then
        warn "Already configured: $cmd"
        return 0
    fi

    # Add to config
    echo "${prefix}${cmd}" >> "$CFG"
    pass "Added: ${prefix}${cmd}"
}

cmd_remove() {
    [ $# -eq 0 ] && fail "Usage: $0 remove <command>"
    local cmd="$1"

    ensure_config

    # Check if exists
    if ! grep -qE "^(#?)?(daemon:)?${cmd}( |$)" "$CFG" 2>/dev/null; then
        fail "Not found: $cmd"
    fi

    # Remove matching lines
    local tmp
    tmp=$(mktemp)
    grep -vE "^(#?)?(daemon:)?${cmd}( |$)" "$CFG" > "$tmp" || true
    mv "$tmp" "$CFG"

    pass "Removed: $cmd"
}

cmd_disable() {
    [ $# -eq 0 ] && fail "Usage: $0 disable <command>"
    local cmd="$1"

    ensure_config

    # Check if exists and not already disabled
    if grep -qE "^${cmd}( |$)" "$CFG" 2>/dev/null; then
        sed -i "s|^${cmd}|#${cmd}|" "$CFG"
        pass "Disabled: $cmd"
    elif grep -qE "^daemon:${cmd}( |$)" "$CFG" 2>/dev/null; then
        sed -i "s|^daemon:${cmd}|#daemon:${cmd}|" "$CFG"
        pass "Disabled: $cmd"
    elif grep -qE "^#${cmd}( |$)" "$CFG" 2>/dev/null; then
        warn "Already disabled: $cmd"
    else
        fail "Not found: $cmd"
    fi
}

cmd_enable() {
    [ $# -eq 0 ] && fail "Usage: $0 enable <command>"
    local cmd="$1"

    ensure_config

    # Check if exists and is disabled
    if grep -qE "^#${cmd}( |$)" "$CFG" 2>/dev/null; then
        sed -i "s|^#${cmd}|${cmd}|" "$CFG"
        pass "Enabled: $cmd"
    elif grep -qE "^#daemon:${cmd}( |$)" "$CFG" 2>/dev/null; then
        sed -i "s|^#daemon:${cmd}|daemon:${cmd}|" "$CFG"
        pass "Enabled: $cmd"
    elif grep -qE "^(daemon:)?${cmd}( |$)" "$CFG" 2>/dev/null; then
        warn "Already enabled: $cmd"
    else
        fail "Not found: $cmd"
    fi
}

cmd_status() {
    ensure_config
    section "Autorun Program Status"
    echo ""

    local running=0
    local total=0
    local daemons=0

    while IFS= read -r line || [ -n "$line" ]; do
        line="$(echo "$line" | sed 's/#.*//' | xargs)"
        [ -z "$line" ] && continue

        total=$((total + 1))

        # Check if daemon
        local cmd="$line"
        if [[ "$line" == daemon:* ]]; then
            daemons=$((daemons + 1))
            cmd="${line#daemon:}"
            cmd="$(echo "$cmd" | xargs)"
        fi

        # Check if running
        local cmd_name
        cmd_name="$(echo "$cmd" | awk '{print $1}')"
        if pgrep -x "$cmd_name" >/dev/null 2>&1; then
            running=$((running + 1))
        fi
    done < "$CFG"

    echo -e "  Total configured:  ${BOLD}$total${NC}"
    echo -e "  Daemons:           ${BOLD}$daemons${NC}"
    echo -e "  Currently running: ${GREEN}$running${NC}"
    echo -e "  Stopped:           ${RED}$((total - running))${NC}"
    echo ""
}

cmd_sync() {
    local project_dir
    project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    local src="$project_dir/dotfiles/labwc/autorun.conf"
    local dst="$HOME/.config/labwc/autorun.conf"

    section "Sync autorun.conf"

    if [ ! -f "$src" ]; then
        fail "Source not found: $src"
    fi

    mkdir -p "$(dirname "$dst")"

    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        pass "Already up to date"
    else
        cp "$src" "$dst"
        pass "Synced: $src → $dst"
    fi
    echo ""
}

# Main
case "${1:-}" in
    list|ls)     cmd_list ;;
    add)         shift; cmd_add "$@" ;;
    remove|rm)   shift; cmd_remove "$@" ;;
    disable)     shift; cmd_disable "$@" ;;
    enable)      shift; cmd_enable "$@" ;;
    status|st)   cmd_status ;;
    sync)        cmd_sync ;;
    help|--help|-h) usage ;;
    *)           usage ;;
esac