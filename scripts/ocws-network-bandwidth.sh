#!/bin/bash
# ocws-network-bandwidth.sh - Per-adapter network bandwidth watcher
#
# Lightweight bandwidth monitoring for each network interface
# "ponytail: this exists" - simple, native approach

set -uo pipefail

OCWS_DIR="${OCWS_DIR:-$HOME/.config/ocws}"
STATE_DIR="$OCWS_DIR/state"
mkdir -p "$STATE_DIR"

# Network bandwidth state
NET_STATS_FILE="$STATE_DIR/network-stats"
NET_HISTORY_FILE="$STATE_DIR/network-history"

# Get list of active network interfaces
get_interfaces() {
    local interfaces
    interfaces=$(ip -o link show 2>/dev/null | awk '/state UP/ {split($0, a, ": "); print a[2]}' | tr '\n' ' ' | sed 's/ $//')
    if [[ -z "$interfaces" ]]; then
        echo "unknown"
    else
        echo "$interfaces"
    fi
}

# Get bytes transferred for an interface
# Note: This requires root access on most systems
collect_interface_stats() {
    local iface="$1"
    local timestamp=$(date +%s)
    
    # Try different methods based on available tools
    local rx_bytes=0
    local tx_bytes=0
    
    if command -v ss >/dev/null 2>&1; then
        # ss can show bytes for connections but not total per interface
        local ss_output
        ss_output=$(ss -s 2>/dev/null | grep "bytes" || echo "")
        
        # Fallback to cat /proc/net/dev (requires root)
        if [[ ! -r /proc/net/dev ]]; then
            return
        fi
        
        local dev_line
        dev_line=$(grep "^  $iface:" /proc/net/dev 2>/dev/null || grep "$iface" /proc/net/dev 2>/dev/null)
        if [[ -n "$dev_line" ]]; then
            # rx_bytes,rx_packets, ... , tx_bytes,tx_packets, ...
            local rx_bytes_field
            local tx_bytes_field
            # Find position of fields
            rx_bytes_field=$(echo "$dev_line" | awk '{for(i=1;i<=NF;i++) if($i=="rx_bytes") print i}')
            tx_bytes_field=$(echo "$dev_line" | awk '{for(i=1;i<=NF;i++) if($i=="tx_bytes") print i}')
            
            if [[ -n "$rx_bytes_field" && -n "$tx_bytes_field" ]]; then
                rx_bytes=$(echo "$dev_line" | awk '{print $'$rx_bytes_field'}' | tr -d ' ')
                tx_bytes=$(echo "$dev_line" | awk '{print $'$tx_bytes_field'}' | tr -d ' ')
            fi
        fi
    fi
    
    # Fallback to using /proc/net/dev directly
    if [[ $rx_bytes -eq 0 || $tx_bytes -eq 0 ]]; then
        if [[ -r /proc/net/dev ]]; then
            local dev_line
            dev_line=$(grep "^  $iface:" /proc/net/dev 2>/dev/null || grep "$iface" /proc/net/dev 2>/dev/null)
            if [[ -n "$dev_line" ]]; then
                # rx_bytes at position 1, tx_bytes at position 9 (after many fields)
                local rx_num
                rx_num=$(echo "$dev_line" | awk '{print $2}')
                local tx_num
                tx_num=$(echo "$dev_line" | awk '{print $10}')
                
                if [[ -n "$rx_num" ]]; then
                    rx_bytes=$rx_num
                fi
                if [[ -n "$tx_num" ]]; then
                    tx_bytes=$tx_num
                fi
            fi
        fi
    fi
    
    echo "$rx_bytes $tx_bytes $timestamp"
}

# Calculate bandwidth (bytes per second)
calculate_bandwidth() {
    local prev="$1"
    local current="$2"
    
    if [[ "$prev" == "0" || "$current" == "0" ]]; then
        echo "0 0"
        return
    fi
    
    local current_rx=$(echo "$current" | awk '{print $2}')
    local current_tx=$(echo "$current" | awk '{print $3}')
    local current_time=$(echo "$current" | awk '{print $4}')
    
    local prev_rx=$(echo "$prev" | awk '{print $2}')
    local prev_tx=$(echo "$prev" | awk '{print $3}')
    local prev_time=$(echo "$prev" | awk '{print $4}')
    
    local time_diff=$((current_time - prev_time))
    if [[ $time_diff -le 0 ]]; then
        time_diff=1
    fi
    
    local rx_diff=$((current_rx - prev_rx))
    local tx_diff=$((current_tx - prev_tx))
    
    if [[ $rx_diff -lt 0 ]]; then
        rx_diff=0
    fi
    if [[ $tx_diff -lt 0 ]]; then
        tx_diff=0
    fi
    
    local rx_rate=$((rx_diff / time_diff))
    local tx_rate=$((tx_diff / time_diff))
    
    echo "$rx_rate $tx_rate"
}

# Update network stats
update_network_stats() {
    local interfaces
    interfaces=$(get_interfaces)
    
    mkdir -p "$STATE_DIR"
    
    for iface in $interfaces; do
        local stats
        stats=$(collect_interface_stats "$iface")
        if [[ -n "$stats" ]]; then
            local rx_bytes=$(echo "$stats" | awk '{print $1}')
            local tx_bytes=$(echo "$stats" | awk '{print $2}')
            local timestamp=$(echo "$stats" | awk '{print $3}')
            
            # Store current stats
            echo "$iface $rx_bytes $tx_bytes $timestamp" >> "$NET_STATS_FILE.tmp"
            
            # Calculate bandwidth
            local prev_stats
            prev_stats=$(grep "^$iface " "$NET_STATS_FILE" 2>/dev/null || echo "0 0 0 0")
            local rx_rate=0
            local tx_rate=0
            
            if [[ "$prev_stats" != "0 0 0 0" ]]; then
                local bw
                bw=$(calculate_bandwidth "$prev_stats" "$stats")
                rx_rate=$(echo "$bw" | awk '{print $1}')
                tx_rate=$(echo "$bw" | awk '{print $2}')
            fi
            
            # Update state file
            sed -i "s/^$iface .*/$iface $rx_bytes $tx_bytes $timestamp/" "$NET_STATS_FILE" 2>/dev/null || echo "$iface $rx_bytes $tx_bytes $timestamp" >> "$NET_STATS_FILE"
            
            # Store in history (keep last hour)
            echo "$iface $rx_rate $tx_rate $timestamp" >> "$NET_HISTORY_FILE.tmp"
            
            # Output JSON for widgets
            jq -n --arg iface "$iface" \
                  --argjson rx_rate "$rx_rate" \
                  --argjson tx_rate "$tx_rate" \
                  --argjson timestamp "$timestamp" \
                  '{iface: $iface, rx_rate: $rx_rate, tx_rate: $tx_rate, timestamp: $timestamp}'
        fi
    done
    
    # Replace files atomically
    mv "$NET_STATS_FILE.tmp" "$NET_STATS_FILE" 2>/dev/null || true
    mv "$NET_HISTORY_FILE.tmp" "$NET_HISTORY_FILE" 2>/dev/null || true
}

# Get current bandwidth for a specific interface
get_interface_bandwidth() {
    local iface="$1"
    local now
    now=$(collect_interface_stats "$iface")
    
    if [[ -z "$now" ]]; then
        echo "0 0"
        return
    fi
    
    local current_rx=$(echo "$now" | awk '{print $1}')
    local current_tx=$(echo "$now" | awk '{print $2}')
    local current_time=$(echo "$now" | awk '{print $3}')
    
    local prev_stats
    prev_stats=$(grep "^$iface " "$NET_STATS_FILE" 2>/dev/null || echo "0 0 0 0")
    
    if [[ "$prev_stats" == "0 0 0 0" ]]; then
        echo "$current_rx $current_tx"
        return
    fi
    
    calculate_bandwidth "$prev_stats" "$now"
}

# Get average bandwidth over a period (last hour)
get_average_bandwidth() {
    local iface="$1"
    local period=${2:-3600}  # default: 1 hour in seconds
    
    if [[ ! -f "$NET_HISTORY_FILE" ]]; then
        echo "0 0"
        return
    fi
    
    local now=$(date +%s)
    local total_rx=0
    local total_tx=0
    local count=0
    
    local line
    while IFS= read -r line; do
        local hist_iface=$(echo "$line" | awk '{print $1}')
        local hist_rx=$(echo "$line" | awk '{print $2}')
        local hist_tx=$(echo "$line" | awk '{print $3}')
        local hist_time=$(echo "$line" | awk '{print $4}')
        
        if [[ "$hist_iface" == "$iface" && $((now - hist_time)) -le $period ]]; then
            total_rx=$((total_rx + hist_rx))
            total_tx=$((total_tx + hist_tx))
            count=$((count + 1))
        fi
    done < "$NET_HISTORY_FILE"
    
    if [[ $count -eq 0 ]]; then
        echo "0 0"
    else
        local avg_rx=$((total_rx / count))
        local avg_tx=$((total_tx / count))
        echo "$avg_rx $avg_tx"
    fi
}

# Format bytes to human readable
format_bytes() {
    local bytes=$1
    
    if [[ $bytes -ge 1073741824 ]]; then
        local gb=$((bytes / 1073741824))
        local mb=$(( (bytes % 1073741824) / 1048576 ))
        if [[ $mb -gt 0 ]]; then
            echo "$gb.$mb GB"
        else
            echo "$gb GB"
        fi
    elif [[ $bytes -ge 1048576 ]]; then
        local mb=$((bytes / 1048576))
        echo "$mb MB"
    elif [[ $bytes -ge 1024 ]]; then
        local kb=$((bytes / 1024))
        echo "$kb KB"
    else
        echo "$bytes B"
    fi
}

# Format bandwidth with units
format_bandwidth() {
    local bytes=$1
    local direction=$2  # "up" or "down"
    
    if [[ $bytes -ge 1048576 ]]; then
        local mbps=$((bytes * 8 / 1048576))
        if [[ $mbps -eq 1 ]]; then
            echo "1 Mbps"
        else
            echo "$mbps Mbps"
        fi
    elif [[ $bytes -ge 1024 ]]; then
        local kbps=$((bytes * 8 / 1024))
        echo "$kbps Kbps"
    else
        local bps=$((bytes * 8))
        echo "$bps bps"
    fi
}

# Generate widget data
export_widget_data() {
    local iface="$1"
    local rx_rate="$2"
    local tx_rate="$3"
    
    mkdir -p "$OCWS_DIR"
    
    # Create widget-data file for the bandwidth widget
    jq -n --arg iface "$iface" \
          --argjson rx_rate "$rx_rate" \
          --argjson tx_rate "$tx_rate" \
          '{iface: $iface, rx_rate: $rx_rate, tx_rate: $tx_rate, timestamp: (now | strftime("%Y-%m-%d %H:%M:%S"))}' > "$OCWS_DIR/widget-bandwidth-data"
}

# Main execution
main() {
    case "${1:-help}" in
        update)
            update_network_stats
            ;;
        get)
            get_interface_bandwidth "$2"
            ;;
        avg)
            get_average_bandwidth "$2" "$3"
            ;;
        cleanup)
            rm -f "$NET_STATS_FILE" "$NET_HISTORY_FILE"
            echo "Network stats cleaned"
            ;;
        *)
            echo ""
            echo "Usage: ${0} <command> [args]"
            echo ""
            echo "Commands:"
            echo "  update      Update network statistics (background)"
            echo "  get IFACE   Get current bandwidth for interface"
            echo "  avg IFACE [SECONDS]   Get average bandwidth over time"
            echo "  cleanup     Clear stored network stats"
            echo ""
            echo "Stats are stored in: ~/.config/ocws/state/network-stats"
            echo "History is stored in: ~/.config/ocws/state/network-history"
            ;;
    esac
}

main "$@"