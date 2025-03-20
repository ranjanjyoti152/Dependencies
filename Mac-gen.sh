#!/bin/bash
# Get current date and time for uniqueness
DATE=$(date +%y%m%d)  # YYMMDD, e.g., 250320
TIME=$(date +%H%M%S)  # HHMMSS, e.g., 192209
SERIAL="$DATE$TIME"   # Combine for uniqueness
MAC="02:16:17:${SERIAL:0:2}:${SERIAL:2:2}:${SERIAL:4:2}"

echo "Setting MAC address to $MAC"

# Show current state of eth0
echo "Current state of eth0:"
ip link show eth0

# Bring interface down
echo "Bringing eth0 down..."
sudo ip link set eth0 down || { echo "Failed to bring eth0 down"; exit 1; }
sleep 2  # Give time for the st_gmac driver to release

# Set the MAC address
echo "Setting new MAC address..."
sudo ip link set eth0 address "$MAC" || { echo "Failed to set MAC address"; exit 1; }

# Bring interface back up
echo "Bringing eth0 up..."
sudo ip link set eth0 up || { echo "Failed to bring eth0 up"; exit 1; }

echo "Done. New state of eth0:"
ip link show eth0
