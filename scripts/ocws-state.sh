#!/bin/bash
# ocws-state.sh — State persistence for OCWS widgets
#
# Simple state storage that survives compositor reloads
# "ponytail: this exists" - using basic text files, not complex databases

set -uo pipefail

OCWS_DIR="${OCWS_DIR:-$HOME/.config/ocws}"
STATE_DIR="$OCWS_DIR/state"
mkdir -p "$STATE_DIR"

# Media player state storage
MEDIA_STATE_FILE="$STATE_DIR/media-state"
PLAYERCTL_STATE_FILE="$STATE_DIR/playerctl-state"
SYSTEM_STATE_FILE="$STATE_DIR/system-state"

# Media player state management
export_media_state() {
    local artist="$1" title="$2" album="$3" 
    local status="$4" position="$5" length="$6" 
    local playing="$7" file_size="$8"
    
    mkdir -p "$(dirname "$MEDIA_STATE_FILE")"
    
    jq -n --arg artist "$artist" --arg title "$title" --arg album "$album" \
          --arg status "$status" --argjson position "$position" --argjson length "$length" \
          --argjson playing "$playing" --argjson file_size "$file_size" \
          '{artist: $artist, title: $title, album: $album, status: $status, position: $position, length: $length, playing: $playing, file_size: $file_size, timestamp: (now | strftime("%Y-%m-%d %H:%M:%S"))}' > "$MEDIA_STATE_FILE"
}

import_media_state() {
    if [[ -f "$MEDIA_STATE_FILE" ]]; then
        cat "$MEDIA_STATE_FILE"
    else
        echo "{\"artist\": \"none\", \"title\": \"none\", \"status\": \"stopped\", \"position\": 0, \"length\": 0, \"playing\": false, \"file_size\": 0, \"timestamp\": \"\"}"
    fi
}

# Playerctl text state (for widget integration)
update_playerctl_state() {
    if [[ $# -ge 8 ]]; then
        local artist="$1" title="$2" album="$3" 
        local status="$4" position="$5" length="$6"
        
        local playing=false
        if [[ "$status" == "playing" ]]; then
            playing=true
        fi
        
        jq -n --arg artist "$artist" --arg title "$title" --arg album "$album" \
              --arg status "$status" --argjson position "$position" --argjson length "$length" \
              --argjson playing "$playing" \
              --argjson file_size "$file_size" \
              '{artist: $artist, title: $title, album: $album, status: $status, position: $position, length: $length, playing: $playing, file_size: $file_size}' > "$PLAYERCTL_STATE_FILE"
        
        echo "Player state updated: $artist - $title ($status)"
    fi
}

# System state persistence
save_system_state() {
    local state_name="$1"
    local state_data="$2"
    
    if [[ -z "$state_name" ]]; then
        echo "Usage: $0 save <state-name> <key=value,key2=value2>"
        return 1
    fi
    
    local state_file="$STATE_DIR/${state_name}-state"
    
    # Simple key=value parsing
    declare -A pairs
    IFS=',' read -ra parts <<< "$state_data"
    for part in "${parts[@]}"; do
        if [[ "$part" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            pairs["$key"]="$value"
        fi
    done
    
    # Create JSON using jq
    local json_pairs=""
    for key in "${!pairs[@]}"; do
        json_pairs="$json_pairs, \"$key\": \"${pairs[$key]}\""
    done
    json_pairs="{${json_pairs#", }}"
    
    echo "$json_pairs" > "$state_file"
    echo "State $state_name saved"
}

load_system_state() {
    local state_name="$1"
    
    local state_file="$STATE_DIR/${state_name}-state"
    
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        echo "{}"
    fi
}

# Widget state sync
sync_widget_state() {
    local media_file="$MEDIA_STATE_FILE"
    local player_file="$PLAYERCTL_STATE_FILE"
    
    if [[ -f "$media_file" && -f "$player_file" ]]; then
        # Merge playerctl state into media state if present
        local title=$(jq -r '.title // empty' "$player_file")
        local artist=$(jq -r '.artist // empty' "$player_file")
        local status=$(jq -r '.status // empty' "$player_file")
        local position=$(jq -r '.position // empty' "$player_file")
        local length=$(jq -r '.length // empty' "$player_file")
        local playing=$(jq -r '.playing // empty' "$player_file")
        
        if [[ "$title" != "" && "$title" != "none" && "$artist" != "" && "$artist" != "none" ]]; then
            # Update media state if new data
            local existing_title=$(jq -r '.title // empty' "$media_file")
            local existing_artist=$(jq -r '.artist // empty' "$media_file")
            
            if [[ "$existing_title" == "none" || "$existing_artist" == "none" || "$artist" != "$existing_artist" || "$title" != "$existing_title" ]]; then
                export_media_state "$artist" "$title" "$(jq -r '.album // empty' "$player_file")" \
                                   "$status" "$position" "$length" "$playing" "$(jq -r '.file_size // 0' "$player_file")"
            fi
        fi
    fi
}

# Media widget integration
update_media_widgets() {
    local media_file="$MEDIA_STATE_FILE"
    
    if [[ -f "$media_file" ]]; then
        local artist=$(jq -r '.artist // "none"' "$media_file")
        local title=$(jq -r '.title // "none"' "$media_file")
        local status=$(jq -r '.status // "none"' "$media_file")
        local position=$(jq -r '.position // 0' "$media_file")
        
        local widget_dir="$OCWS_DIR/dotfiles/ocws"
        
        # Update media-player.widget if needed
        local player_widget="$widget_dir/media-player.widget"
        if [[ -f "$player_widget" && ("$artist" == "none" || "$title" == "none") ]]; then
            sed -i 's|If(XMediaStatus != "none", "Artist: ".*"No media playing")|If(XMediaStatus != "none", If(XMediaArtist != "none", "Artist: " + XMediaArtist + "\\n", "") + If(XMediaTitle != "none", "Title: " + XMediaTitle + "\\n", "") + "Status: " + XMediaStatus + "\\n" + If(XMediaPosFmt != "", "Position: " + XMediaPosFmt, ""), "No media playing")|g' "$player_widget"
        fi
        
        # Update media.widget for cover art if cleared
        local media_widget="$widget_dir/media.widget"
        if [[ -f "$media_widget" && "$artist" == "none" && "$title" == "none" ]]; then
            # Restore default cover art image value
            sed -i 's|value = If(XArt != "none",.*|value = "/tmp/ocws-cover.jpg"|g' "$media_widget"
        fi
    fi
}

# Media state cleanup
clean_media_state() {
    if [[ -f "$MEDIA_STATE_FILE" ]]; then
        local artist=$(jq -r '.artist // "none"' "$MEDIA_STATE_FILE")
        local title=$(jq -r '.title // "none"' "$MEDIA_STATE_FILE")
        local status=$(jq -r '.status // "none"' "$MEDIA_STATE_FILE")
        
        if [[ "$artist" == "none" && "$title" == "none" && "$status" == "none" ]]; then
            rm -f "$MEDIA_STATE_FILE" "$PLAYERCTL_STATE_FILE"
            echo "Media state cleaned (no active player)"
        fi
    fi
}

# System music integration (for maintaining music widget with art)
maintain_music_widget() {
    local artist=$(jq -r '.artist // "none"' "$MEDIA_STATE_FILE" 2>/dev/null || echo "none")
    local title=$(jq -r '.title // "none"' "$MEDIA_STATE_FILE" 2>/dev/null || echo "none")
    local status=$(jq -r '.status // "none"' "$MEDIA_STATE_FILE" 2>/dev/null || echo "none")
    
    if [[ -d "$OCWS_DIR/dotfiles/ocws" ]]; then
        local music_widget="$OCWS_DIR/dotfiles/ocws/music.widget"
        
        # Update music widget scanner with media state
        if [[ -f "$music_widget" ]]; then
            if [[ "$artist" != "none" && "$title" != "none" ]]; then
                # Add scanner to fetch music widget data
                if ! grep -q "XMusicArtist" "$music_widget"; then
                    cat >> "$music_widget" << 'EOF'
  exec("/bin/sh -c 'cat ~/.config/ocws/state/media-state 2>/dev/null || echo {}'") {
    XMusicData = Grab(First)
  }
EOF
                    echo "Added music widget scanner for state data"
                fi
            else
                # Clean up music widget scanner if no active music
                sed -i '/XMusicData/d' "$music_widget"
            fi
        fi
    fi
}

# Backup and restore state
backup_state() {
    local backup_dir="$STATE_DIR/backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    cp -r "$STATE_DIR"/* "$backup_dir/" 2>/dev/null || true
    echo "State backed up to: $backup_dir"
}

# Verify state system
verify_state() {
    local issues=""
    
    for state_file in "$STATE_DIR"/*.json "$STATE_DIR"/*.state 2>/dev/null; do
        if [[ -f "$state_file" ]]; then
            if ! jq . "$state_file" >/dev/null 2>&1; then
                issues="$issues $state_file (invalid JSON)"
            fi
        fi
    done
    
    if [[ -z "$issues" ]]; then
        echo "All state files are valid"
    else
        echo "State issues:$issues"
    fi
}

# Main execution
main() {
    case "${1:-help}" in
        export)
            update_playerctl_state "$@"
            ;;
        sync)
            sync_widget_state
            update_media_widgets
            maintain_music_widget
            pass "Widget state synchronized"
            ;;
        save)
            save_system_state "$@"
            ;;
        load)
            load_system_state "$2"
            ;;
        backup)
            backup_state
            ;;
        verify)
            verify_state
            ;;
        clean)
            clean_media_state
            ;;
        *)
            echo ""
            echo "Usage: ${0} <command> [args]"
            echo ""
            echo "Commands:"
            echo "  export <artist> <title> <album> <status> <position> <length> <playing>"
            echo "    Export media player state to files"
            echo ""
            echo "  sync        Sync state to widgets (auto-update media widgets)"
            echo "  backup      Create backup of all state files"
            echo "  verify      Verify state file integrity"
            echo "  clean       Clean up empty media state"
            echo ""
            echo "  save <name> <key=value...>    Save system state file"
            echo "  load <name>                  Load system state file"
            echo ""
            echo "State files are stored in: ~/.config/ocws/state/"
            ;;
    esac
}

main "$@"