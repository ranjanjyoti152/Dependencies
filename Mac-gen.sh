#!/bin/bash
# Get current date and time for uniqueness
DATE=$(date +%y%m%d)  # YYMMDD, e.g., 250320
TIME=$(date +%H%M%S)  # HHMMSS, e.g., 192209
SERIAL="$DATE$TIME"   # Combine for uniqueness

# Construct the MAC address
MAC="02:16:17:${SERIAL:0:2}:${SERIAL:2:2}:${SERIAL:4:2}"

echo "Setting MAC address to $MAC"

# Bring the interface down, set the MAC, and bring it back up
sudo ip link set eth0 down
sudo ip link set eth0 address "$MAC"
sudo ip link set eth0 up
