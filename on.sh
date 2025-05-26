#!/bin/bash

echo "[*] Restoring WiFi interface to managed mode..."
sudo ip link set wlan0 down
sudo iwconfig wlan0 mode managed
sudo ip link set wlan0 up
sudo systemctl restart NetworkManager
echo "[✓] WiFi should now be working. Try reconnecting."
