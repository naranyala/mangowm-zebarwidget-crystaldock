#!/bin/bash
# playerctl.sh — Media player control (repeat from alt+p)
#
# Modes: play, pause, stop, next, previous, play-pause, seek, metadata, volume
#

MODE="${1:-help}"
STEP="${2:--10}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

# Get playerctl data if available
run_playerctl() {
    if command -v playerctl >/dev/null 2>&1; then
        playerctl "$@"
    else
        echo "Playerctl not installed. Please install it first."
        exit 1
    fi
}

# Get current song info
song_info() {
    local output
    output=$(run_playerctl metadata --format "{{title}} — {{artist}}" 2>/dev/null || echo "No song playing")
    
    if [[ "$output" != "No song playing" ]]; then
        local title=$(run_playerctl metadata --format "{{title}}" 2>/dev/null | sed 's/\\/\\\\/g')
        local artist=$(run_playerctl metadata --format "{{artist}}" 2>/dev/null | sed 's/\\/\\\\/g')
        local status=$(run_playerctl status 2>/dev/null | tr '[:upper:]' '[:lower:]')
        local position=$(run_playerctl position 2>/dev/null | cut -d '.' -f1)
        local length=$(run_playerctl length 2>/dev/null | cut -d '.' -f1)
        
        echo "{\"title\": \"$title\", \"artist\": \"$artist\", \"status\": \"$status\", \"position\": $position, \"length\": $length, \"playing\": $([[ \"$status\" = \"playing\" ]] && echo true || echo false)}"
    else
        echo "{\"title\": \"none\", \"artist\": \"none\", \"status\": \"stopped\", \"position\": 0, \"length\": 0, \"playing\": false}"
    fi
}

# Play/Pause toggle
play_pause() {
    run_playerctl play-pause
    pass "Playback toggled"
}

# Play
play() {
    run_playerctl play
    pass "Playing"
}

# Pause
pause() {
    run_playerctl pause
    pass "Paused"
}

# Stop
stop() {
    run_playerctl stop
    pass "Stopped"
}

# Next track
next() {
    run_playerctl next
    pass "Next track"
}

# Previous track
previous() {
    run_playerctl previous
    pass "Previous track"
}

# Seek forward
seek_forward() {
    local seconds=${2:-10}
    run_playerctl seek "+${seconds}s"
    pass "Seeked forward ${seconds}s"
}

# Seek backward
seek_backward() {
    local seconds=${2:-10}
    run_playerctl seek "-${seconds}s"
    pass "Seeked backward ${seconds}s"
}

# Jump to position
seek_to() {
    local position=${2:-0}
    run_playerctl seek "${position}s"
    pass "Jumped to ${position}s"
}

# Volume control (playerctl uses microphone for volume, use wpctl for system)
volume_up() {
    if command -v wpctl >/dev/null 2>&1; then
        local step=${2:-5%}
        wpctl set-volume @DEFAULT_AUDIO_SINK@ "$step"+
        pass "Volume up $step"
    else
        warn "wpctl not available for system volume control"
    fi
}

volume_down() {
    if command -v wpctl >/dev/null 2>&1; then
        local step=${2:-5%}
        wpctl set-volume @DEFAULT_AUDIO_SINK@ "$step"-
        pass "Volume down $step"
    else
        warn "wpctl not available for system volume control"
    fi
}

volume_mute() {
    if command -v wpctl >/dev/null 2>&1; then
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        pass "Mute toggled"
    else
        warn "wpctl not available for system volume control"
    fi
}

# Music widget integration
export_media_state() {
    local artist=$(echo "$1" | jq -r '.artist')
    local title=$(echo "$1" | jq -r '.title')
    local status=$(echo "$1" | jq -r '.status')
    local position=$(echo "$1" | jq -r '.position')
    
    local media_file="$HOME/.config/ocws/widget-media-state"
    mkdir -p "$(dirname "$media_file")"
    
    jq -n --arg artist "$artist" --arg title "$title" --arg status "$status" --argjson position "$position" \
          --argjson playing "$([[ \"$status\" = \"playing\" ]] && echo true || echo false)" \
          '{artist: $artist, title: $title, status: $status, position: $position, playing: $playing}' > "$media_file"
    
    pass "Media state exported: $artist - $title ($status)"
}

# Main execution
main() {
    case "$MODE" in
        play|pause|stop)
            play_pause
            if [[ "$MODE" == "play" ]]; then play
            elif [[ "$MODE" == "pause" ]]; then pause
            else stop
            fi
            ;;
        play-pause)
            play_pause
            ;;
        next|forward)
            next
            ;;
        previous|back)
            previous
            ;;
        seek-forward|seek+|--10|--30|--60)
            seek_forward "${MODE: -3}"
            ;;
        seek-backward|seek-|seek--|-10|-30|-60)
            seek_backward "${MODE: -3}"
            ;;
        volume-up|volup|up)
            volume_up
            ;;
        volume-down|voldown|down)
            volume_down
            ;;
        volume-mute|volmute|mute)
            volume_mute
            ;;
        info|metadata|status|song)
            song_info
            ;;
        export)
            song_info | export_media_state
            ;;
        help|--help|-h|*)
            echo ""
            echo "${BOLD}Player Control${NC}"
            echo ""
            echo "Usage: ${0} <command> [value]"
            echo ""
            echo "Commands:"
            echo "  play           Start playback"
            echo "  pause          Pause playback"
            echo "  stop           Stop playback"
            echo "  play-pause     Toggle play/pause"
            echo "  next|forward   Skip to next track"
            echo "  previous|back  Skip to previous track"
            echo "  seek-forward N Seek forward N seconds (default: 10)"
            echo "  seek-backward N Seek backward N seconds (default: 10)"
            echo "  volume-up [N]  Increase volume (default: 5%)"
            echo "  volume-down [N] Decrease volume (default: 5%)"
            echo "  volume-mute    Toggle mute"
            echo "  info|metadata   Show current song info"
            echo "  export         Export current song to widget state"
            echo ""
            ;;
        *)
            echo "Unknown command: $MODE"
            echo ""
            echo "Usage: ${0} <command> [value]"
            echo ""
            echo "Run ${0} help for more information"
            exit 1
            ;;
    esac
}

main "$@"