#!/usr/bin/env bash

# General System Health Check Script
# Focuses on Disks, Memory, Networking, Services, and Developer Environment

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}       General System Health Check       ${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

# 1. Disk Space
echo -e "${CYAN}[1/5] Checking Disk Space...${NC}"
df -h / /home 2>/dev/null | awk 'NR>1 {print $5 " " $6}' | while read p; do
    usage=$(echo $p | cut -d'%' -f1)
    mount=$(echo $p | cut -d' ' -f2)
    if [ "$usage" -ge 90 ]; then
        echo -e "  ${RED}[WARN]${NC} Partition $mount is critically full at ${usage}% capacity!"
    elif [ "$usage" -ge 75 ]; then
        echo -e "  ${YELLOW}[INFO]${NC} Partition $mount is getting full at ${usage}% capacity."
    else
        echo -e "  ${GREEN}[OK]${NC}   Partition $mount has plenty of space (${usage}% used)."
    fi
done
echo ""

# 2. Memory & Swap
echo -e "${CYAN}[2/5] Checking Memory...${NC}"
free -m | awk 'NR==2{printf "  [INFO] RAM Usage: %sMB / %sMB (%.2f%%)\n", $3,$2,$3*100/$2 } NR==3{if($2>0){printf "  [INFO] Swap Usage: %sMB / %sMB (%.2f%%)\n", $3,$2,$3*100/$2}else{printf "  [INFO] Swap is disabled or 0MB.\n"}}'
echo ""

# 3. System Services & Security
echo -e "${CYAN}[3/5] Checking Core Services & Security...${NC}"
services=("NetworkManager" "bluetooth" "systemd-logind" "firewalld")
for s in "${services[@]}"; do
    if systemctl is-active --quiet $s; then
        echo -e "  ${GREEN}[OK]${NC}   $s is running."
    else
        echo -e "  ${YELLOW}[INFO]${NC} $s is NOT running."
    fi
done

if command -v sestatus &> /dev/null; then
    selinux_mode=$(sestatus | grep "Current mode:" | awk '{print $3}')
    echo -e "  [INFO] SELinux is set to: $selinux_mode"
fi
echo ""

# 4. Networking
echo -e "${CYAN}[4/5] Checking Network Connectivity...${NC}"
if ping -c 1 -W 2 1.1.1.1 &> /dev/null; then
    echo -e "  ${GREEN}[OK]${NC}   Internet connection is active (Pinged 1.1.1.1)."
else
    echo -e "  ${RED}[FAIL]${NC} No internet connection detected."
fi

if ping -c 1 -W 2 google.com &> /dev/null; then
    echo -e "  ${GREEN}[OK]${NC}   DNS resolution is working."
else
    echo -e "  ${RED}[FAIL]${NC} DNS resolution is failing."
fi
echo ""

# 5. Developer / Dotfiles Environment
echo -e "${CYAN}[5/5] Checking Developer Environment...${NC}"
if [ -f "$HOME/.ssh/id_rsa" ] || [ -f "$HOME/.ssh/id_ed25519" ]; then
    echo -e "  ${GREEN}[OK]${NC}   Standard SSH keys found."
else
    echo -e "  ${YELLOW}[WARN]${NC} No standard SSH keys found in ~/.ssh/."
fi

if git config --global user.email &> /dev/null; then
    echo -e "  ${GREEN}[OK]${NC}   Git global user.email is configured."
else
    echo -e "  ${YELLOW}[WARN]${NC} Git global user.email is NOT configured."
fi
echo ""

echo -e "${CYAN}=========================================${NC}"
echo "Health check complete."
