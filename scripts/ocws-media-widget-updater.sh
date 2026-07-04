#!/bin/bash
# ocws-media-widget-updater.sh - Enhanced media widget integration
# "ponytail: this exists" - the simplest solution for album art in OCWS

set -uo pipefail

OCWS_DIR="${OCWS_DIR:-$HOME/.config/ocws}"
MEDIA_DIR="$OCWS_DIR/dotfiles/ocws"
ART_DIR="$OCWS_DIR/cover-art"
mkdir -p "$ART_DIR"

# Fetch album art from MusicBrainz
fetch_album_art() {
    local artist="$1"
    local title="$2"
    
    if [[ "$artist" == "none" || "$title" == "none" ]]; then
        artist="Unknown Artist"
        title="Unknown Title"
    fi
    
    local safe_name="${artist//["']/ }-${title//["']/ }"
    local art_file="$ART_DIR/${safe_name// /-}.png"
    
    if [[ -f "$art_file" ]]; then
        echo "$art_file"
        return
    fi
    
    # Try MusicBrainz API
    local art_url=""
    art_url=$(curl -s "https://musicbrainz.org/ws/2/recording/?query=artist:${artist// /+}%20title:${title// /+}&fmt=json&inc=video+images&limit=1" |
        jq -r '.recordings[0].video.images[0] // empty' | head -1)
    
    if [[ -n "$art_url" ]]; then
        local temp_file="$ART_DIR/tmp-${safe_name// /-}.png"
        if curl -s -L "$art_url" -o "$temp_file"; then
            # Scale and convert if needed
            if command -v convert >/dev/null 2>&1; then
                convert "$temp_file" -resize 120x120 "$art_file"
            else
                cp "$temp_file" "$art_file"
            fi
            rm -f "$temp_file"
            echo "Downloaded: $art_file"
            return
        fi
    fi
    
    echo ""
}

# Find album art directory path
find_art_path() {
    local artist="$1"
    local title="$2"
    
    if [[ "$artist" == "none" || "$title" == "none" ]]; then
        echo "resource:///org/gnome/settings-daemon/audio/voices/warning_sound.ogg"  # No art fallback
        return
    fi
    
    local safe_name="${artist//["']/ }-${title//["']/ }"
    local art_file="$ART_DIR/${safe_name// /-}.png"
    
    if [[ -f "$art_file" ]]; then
        echo "file://$art_file"
    else
        echo "resource:///org/gnome/settings-daemon/audio/voices/warning_sound.ogg"
    fi
}

# Update media-player.widget with cover art support
update_media_widget() {
    local widget_path="$MEDIA_DIR/media-player.widget"
    
    if [[ ! -f "$widget_path" ]]; then
        echo "Warning: media-player.widget not found" >&2
        return
    fi
    
    local cover_art="file://${ART_DIR}/default-cover.png"
    if [[ ! -f "${ART_DIR}/default-cover.png" ]]; then
        # Get fallback cover
        local fallback_url="https://picsum.photos/seed/ocws/120/120.png"
        curl -s -o "${ART_DIR}/default-cover.png" "$fallback_url"
    fi
    
    # Add cover art extraction to scanner section
    if ! grep -q "XCoverArt" "$widget_path"; then
        sed -i '/exec.*playerctl metadata --format.*title/ a\\   exec("/bin/sh -c \"curl -s \"https://picsum.photos/seed/ocws/120/120.png\" -o \"${ART_DIR:-~/.config/ocws/cover-art}/default-cover.png\" || true\" ) { XCoverArt = Grab(First) }' "$widget_path"
    fi
    
    # Update the widget popup to include cover art
    local media_popup_section="-- MediaPopup --"
    if grep -q "$media_popup_section" "$widget_path"; then
        # Find and update the image section
        sed -i '/image {/a\\      value = If(XCoverArt != \"none\", \"file://'$cover_art'\", \"resource:///org/gnome/settings-daemon/audio/voices/warning_sound.ogg\")' "$widget_path"
    fi
    
    echo "Updated $widget_path with cover art support"
}

# Update media.widget for cover art display
update_media_widget_simple() {
    local widget_path="$MEDIA_DIR/media.widget"
    
    if [[ ! -f "$widget_path" ]]; then
        return
    fi
    
    # Find the media popup and add cover art image if not present
    if ! grep -q '/tmp/ocws-cover.jpg' "$widget_path"; then
        # Get default cover
        local default_cover="file://${ART_DIR}/default-cover.png"
        if [[ ! -f "${ART_DIR}/default-cover.png" ]]; then
            curl -s -o "${ART_DIR}/default-cover.png" "https://picsum.photos/seed/ocws/120/120.png"
        fi
        
        # Add cover art image configuration
        cat >> "$widget_path" << 'EOF'

  image {
    value = If(XCoverArt != "none", file://~/.config/ocws/cover-art/album-cover.png, "${ART_DIR}/default-cover.png")
    interval = 2000
    style = "media_cover"
  }

EOF
    fi
    
    echo "Updated $widget_path with cover art display"
}

# Sync theme to update CSS styling for cover art
update_theme_css() {
    local theme_dir="$HOME/.config/ocws"
    local css_file="$theme_dir/ocws.css"
    
    if [[ -f "$css_file" ]]; then
        # Ensure media_cover style exists
        if ! grep -q "\.media_cover {" "$css_file"; then
            cat >> "$css_file" << 'EOF'

/* Album art styling */
image.media_cover {
  min-width: 120px;
  min-height: 120px;
  border-radius: 12px;
  border: 1px solid rgba(255,255,255,0.1);
  margin-bottom: 10px;
  -GtkWidget-align: 0.5;
  -GtkWidget-valign: center;
  -GtkWidget-halign: center;
  transition: transform 0.3s ease;
}

image.media_cover:hover {
  transform: scale(1.05);
}

EOF
        fi
    fi
}

# Generate widget-art-data with current album info
create_widget_data() {
    local data_file="$OCWS_DIR/widget-art-data"
    mkdir -p "$OCWS_DIR"
    
    if [[ -f "/tmp/ocws-current-song" ]]; then
        local artist=$(jq -r '.artist // "none"' "/tmp/ocws-current-song" 2>/dev/null || echo "none")
        local title=$(jq -r '.title // "none"' "/tmp/ocws-current-song" 2>/dev/null || echo "none")
        
        if [[ "$artist" != "none" && "$title" != "none" ]]; then
            jq -n --arg artist "$artist" --arg title "$title" \
                  --arg uri "$ART_DIR/${artist// /-}-${title// /-}.png" \
                  '{artist: $artist, title: $title, uri: $uri}' > "$data_file"
            echo "Created widget data: $artist - $title"
        fi
    fi
}

# Main execution
main() {
    case "${1:-}" in
        init)
            update_media_widget
            update_media_widget_simple
            update_theme_css
            create_widget_data
            echo "OCWS media widgets initialized with cover art support"
            ;;
        update)
            update_media_widget
            update_media_widget_simple
            echo "Media widgets updated"
            ;;
        fetch)
            local artist="$2"
            local title="$3"
            if [[ $# -ge 3 ]]; then
                local art_path
                art_path=$(fetch_album_art "$artist" "$title")
                if [[ -n "$art_path" ]]; then
                    echo "Album art available at: $art_path"
                fi
                create_widget_data
            else
                echo "Usage: $0 fetch ARTIST TITLE"
            fi
            ;;
        *)
            echo "Usage: $0 {init|update|fetch ARTIST TITLE}"
            echo ""
            echo "This script enhances OCWS media widgets with album art support."
            ;;
    esac
}

main "$@"