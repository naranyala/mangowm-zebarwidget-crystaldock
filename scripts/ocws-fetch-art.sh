#!/bin/bash
# ocws-fetch-art — Fetch album art for OCWS media widget
# 
# Usage:
#   ocws-fetch-art TITLE ARTIST OUTPUT_PATH
#   ocws-fetch-art --batch FILE_LIST
# 
# Fetches album art from provided URLs or searches MusicBrainz/discogs
# and saves to $HOME/.config/ocws/cover-art/

set -uo pipefail

OCWS_DIR="$HOME/.config/ocws"
ART_DIR="$OCWS_DIR/cover-art"
mkdir -p "$ART_DIR"

# Store album art URLs (can be populated from a web service)
ART_CACHE_FILE="$OCWS_DIR/album-art-cache"

# Fallback to local icons if no art found
LOCAL_FALLBACKS=(
    "icons/misc/music-album-symbolic"
    "icons/misc/multimedia-player-symbolic"
)

get_art() {
    local artist="$1"
    local title="$2"
    local artist_safe="${artist//["']/ }"
    local title_safe="${title//["']/ }"
    local cache_key="${artist_safe}::${title_safe}"
    
    # Check cache for pre-fetched art
    if [[ -f "$ART_CACHE_FILE" ]]; then
        local cached_url
        cached_url=$(grep "^${cache_key}" "$ART_CACHE_FILE" | cut -d'=' -f2)
        if [[ -n "$cached_url" ]]; then
            fetch_and_cache "$cached_url" "$1-$2.png"
            return
        fi
    fi
    
    # Try MusicBrainz API first
    local mb_art_url
    mb_art_url=$(curl -s "https://musicbrainz.org/ws/2/recording/?query=artist:${artist_safe}%20title:${title_safe}&fmt=json" | jq -r '.recordings[0].video .images[0] // empty' | head -1)
    
    if [[ -n "$mb_art_url" ]]; then
        fetch_and_cache "$mb_art_url" "$1-$2.png"
        return
    fi
    
    # Try Discogs API as fallback
    local discogs_token="${DISCOGS_TOKEN:-}"
    if [[ -n "$discogs_token" ]]; then
        local discogs_art_url
        discogs_art_url=$(curl -s "https://api.discogs.com/database/search?q=${artist_safe}%20${title_safe}&type=release&format=album" \
            -H "Authorization: Discogs token=$discogs_token" | jq -r '.releases[0].images[0] // empty' | head -1)
        
        if [[ -n "$discogs_art_url" ]]; then
            fetch_and_cache "$discogs_art_url" "$1-$2.png"
            return
        fi
    fi
    
    # Fallback to default icon
    local default_icon
    default_icon=$(find "$OCWS_DIR" -type f \( -name "*.png" -o -name "*.svg" \) | grep -E "(album|music|media)" | head -1)
    
    if [[ -n "$default_icon" ]]; then
        cp "$default_icon" "$ART_DIR/$1-$2.png"
        echo "Using default icon: $ART_DIR/$1-$2.png"
    else
        local icon_path
        icon_path="$ART_DIR/$1-$2.png"
        find "$OCWS_DIR" -name "${LOCAL_FALLBACKS[0]}.png" -o -name "${LOCAL_FALLBACKS[0]}.svg" 2>/dev/null | head -1 | xargs -I {} cp {} "$icon_path"
        if [[ -f "$icon_path" ]]; then
            echo "Used fallback icon: $icon_path"
        fi
    fi
}

fetch_and_cache() {
    local url="$1"
    local filename="$2"
    local cache_file="$ART_DIR/$filename"
    
    echo "Fetching album art from: $url"
    
    if curl -s "$url" -o "$cache_file"; then
        # Validate file
        if [[ -f "$cache_file" ]]; then
            local file_size
            file_size=$(du -h "$cache_file" | cut -f1)
            echo "Downloaded: $filename ($file_size)"
            
            # Update cache file
            if [[ ! -f "$ART_CACHE_FILE" ]]; then
                touch "$ART_CACHE_FILE"
            fi
            sed -i "/^${cache_key^}=/d" "$ART_CACHE_FILE"
            echo "^${cache_key^}=${url}" >> "$ART_CACHE_FILE"
            
            return 0
        fi
    fi
    
    echo "Failed to download album art from: $url"
}

fetch_art_for_widget() {
    local json_file="$OCWS_DIR/widget-art-data"
    
    if [[ -f "$json_file" ]]; then
        local title artist
        title=$(jq -r '.title // "none"' "$json_file")
        artist=$(jq -r '.artist // "none"' "$json_file")
        
        if [[ "$title" != "none" && "$artist" != "none" ]]; then
            get_art "$artist" "$title"
            
            local art_path="$ART_DIR/$artist-$title.png"
            if [[ -f "$art_path" ]]; then
                echo "$art_path"
                return
            fi
        fi
    fi
    
    return 1
}

update_widget_data() {
    local json_file="$OCWS_DIR/widget-art-data"
    mkdir -p "$OCWS_DIR"
    
    if [[ $# -ge 2 ]]; then
        local title="$1"
        local artist="$2"
        jq -n --arg title "$title" --arg artist "$artist" '{title: $title, artist: $artist}' > "$json_file"
        echo "Updated widget data: $artist - $title"
    else
        jq 'del(.title // empty, .artist // empty)' "$json_file" > "${json_file}.tmp" && mv "${json_file}.tmp" "$json_file"
        rm -f "$json_file"
        echo "Cleared widget data"
    fi
}

main() {
    case "${1:-}" in
        --batch)
            shift
            while [[ $# -gt 0 ]]; do
                local file="$1"
                if [[ -f "$file" ]]; then
                    local title artist
                    title=$(jq -r '.title // ""' "$file")
                    artist=$(jq -r '.artist // ""' "$file")
                    if [[ -n "$title" && -n "$artist" ]]; then
                        get_art "$artist" "$title"
                    fi
                fi
                shift
            done
            ;;
        *)
            if [[ $# -ge 2 ]]; then
                get_art "$1" "$2"
            else
                echo "Usage: $0 ARTIST TITLE | $0 --batch FILE_LIST"
                exit 1
            fi
            ;;
    esac
}

main "$@"