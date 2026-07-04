#!/bin/bash
# ocws-media-art.sh - Integrate album art with media widget
# 
# This script updates the media widgets to use album art, similar to 
# how GNOME media players display cover art. It integrates with both
# media.widgets with optional cover art support.

set -uo pipefail

OCWS_DIR="${OCWS_DIR:-$HOME/.config/ocws}"
MEDIA_DIR="$OCWS_DIR/dotfiles/ocws"
ART_DIR="$OCWS_DIR/cover-art"
mkdir -p "$ART_DIR"

# Find artist/title from running media player
extract_media_info() {
    local info_file="$OCWS_DIR/widget-info"
    mkdir -p "$OCWS_DIR"
    
    if [[ -f "/tmp/ocws-media-state" ]]; then
        cat "/tmp/ocws-media-state" > "$info_file"
    else
        # Try to extract from widgets
        echo "{}" > "$info_file"
    fi
    
    local artist=$(jq -r '.artist // "none"' "$info_file")
    local title=$(jq -r '.title // "none"' "$info_file")
    local file_size=$(jq -r '.file_size // 0' "$info_file")
    
    # For files > 50MB, skip to avoid issues
    if [[ $file_size -gt 50000000 ]]; then
        artist="$1 - $title"
        title="none"
    fi
    
    echo "$artist" "$title"
}

# Download and scale album art
fetch_and_scale_art() {
    local artist="$1"
    local title="$2"
    local output_dir="$ART_DIR"
    
    if [[ "$artist" == "none" || "$title" == "none" ]]; then
        return 1
    fi
    
    local safe_name="${artist//["']/ }-${title//["']/ }"
    local art_file="$output_dir/${safe_name}.png"
    
    if [[ -f "$art_file" ]]; then
        echo "$art_file"
        return
    fi
    
    # Try multiple art sources
    local art_sources=(
        "https://musicbrainz.org/ws/2/recording/?query=artist:${artist// /+}%20title:${title// /+}&fmt=json&inc=video+images&limit=1"
        "https://api.spotify.com/v1/search?q=artist:${artist}%20track:${title}&type=track"
        "https://coverartarchive.org/release/${artist// /+}-${title// /+}"
    )
    
    local img_url=""
    for source in "${art_sources[@]}"; do
        img_url=$(curl -s "$source" | jq -r '.recordings[0].video.images[0] // .images[0] // empty' | head -1)
        if [[ -n "$img_url" ]]; then
            break
        fi
    done
    
    if [[ -n "$img_url" ]]; then
        local temp_file="$ART_DIR/tmp-${safe_name}.png"
        if curl -s -L "$img_url" -o "$temp_file"; then
            # Scale to appropriate size
            if command -v convert >/dev/null 2>&1; then
                convert "$temp_file" -resize 120x120 "$art_file"
            else
                cp "$temp_file" "$art_file"
            fi
            rm -f "$temp_file"
            echo "Downloaded: $art_file"
            return 0
        fi
    fi
    
    # Use fallback
    if [[ ! -f "office-art.png" ]]; then
        local fallback_url="https://picsum.photos/seed/ocws/120/120.png"
        curl -s -o "office-art.png" "$fallback_url"
    fi
    if [[ -f "office-art.png" ]]; then
        cp "office-art.png" "$art_file"
        echo "Using placeholder: $art_file"
        return 0
    fi
    
    return 1
}

# Update media widget config to include cover art
update_media_widget_config() {
    local artist="$1"
    local title="$2"
    
    if [[ "$artist" == "none" || "$title" == "none" ]]; then
        artist="Unknown Artist"
        title="Unknown Title"
    fi
    
    local media_player_widget="$MEDIA_DIR/media-player.widget"
    local media_widget="$MEDIA_DIR/media.widget"
    
    # Add cover art handler to media-player widget if needed
    if [[ -f "$media_player_widget" ]]; then
        grep -q "XCoverArt" "$media_player_widget" || (
            cat >> "$media_player_widget" << 'EOF'
  exec("/bin/sh -c 'echo \"$XTitle:$XArtist\",$XCoverArt 2>/dev/null'") {
    XCoverArtReq = Grab(First)
  }
EOF
        )
    fi
    
    # Add cover art handling to popup if needed
    if [[ -f "$media_widget" ]]; then
        local art_file="$ART_DIR/$(echo "${artist//["']/ }-${title//["']/ }.png" | tr '[:upper:]' '[:lower:]')"
        if [[ -f "$art_file" ]]; then
            # Update the image reference in the popup
            sed -i "s|.*\\(value = \"/tmp/ocws-cover.jpg\"\\).*|\1 \"value = \"$art_file\",\n      \"style = 'media_cover'\",\n      \"interval = 2000\",\n      \"value = If(XCoverArtReq != 'empty', '${artist} — ${title}', 'No album art found')\",|" "$media_widget" 2>/dev/null || true
        fi
    fi
}

# Monitor media player state and fetch art
monitor_media_for_art() {
    local info_file="$OCWS_DIR/widget-art-requests"
    mkdir -p "$OCWS_DIR"
    
    while true; do
        if [[ -f "/tmp/ocws-media-state" ]]; then
            local artist title
            read -r artist title <<<$(extract_media_info)
            
            if [[ "$artist" != "none" && "$title" != "none" ]]; then
                local art_file
                art_file=$(fetch_and_scale_art "$artist" "$title")
                update_media_widget_config "$artist" "$title"
                
                # Store request for widgets
                echo "$title:$artist" > "$info_file"
                echo "Art fetching complete: $title — $artist"
            fi
        fi
        
        sleep 30
    done
}

# Main execution
main() {
    case "${1:-}" in
        monitor)
            echo "Starting media art monitor..."
            monitor_media_for_art
            ;;
        fetch)
            local artist="$2"
            local title="$3"
            if [[ $# -ge 3 ]]; then
                fetch_and_scale_art "$artist" "$title"
            else
                echo "Usage: $0 fetch ARTIST TITLE"
            fi
            ;;
        update)
            local artist="$2"
            local title="$3"
            if [[ $# -ge 3 ]]; then
                update_media_widget_config "$artist" "$title"
            else
                echo "Usage: $0 update ARTIST TITLE"
            fi
            ;;
        *)
            echo "Usage: $0 {monitor|fetch ARTIST TITLE|update ARTIST TITLE}"
            ;;
    esac
}

main "$@"