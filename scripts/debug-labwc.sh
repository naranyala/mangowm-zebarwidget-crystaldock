#!/bin/bash
# debug-labwc.sh — Launch a nested labwc session for debugging
# 
# This script runs a completely separate instance of labwc as a window
# inside your current session. This allows you to safely test changes to:
#  - ~/.config/labwc/rc.xml
#  - ~/.config/labwc/environment
#  - ~/.config/labwc/autostart
# without logging out, restarting, or killing your open applications.

set -euo pipefail

echo "=========================================================="
echo " Starting Nested labwc Debug Session"
echo "=========================================================="
echo "• The nested compositor will appear in a new window."
echo "• It will run your current ~/.config/labwc/ files."
echo "• Close the nested window (or press your Exit keybind inside it) to stop."
echo "• Check the terminal output below for labwc error logs."
echo "=========================================================="

# Run labwc with verbose logging and start a terminal inside it automatically
labwc --verbose -s "contour"
