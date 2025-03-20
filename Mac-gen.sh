#!/bin/bash
# Get current date and time for uniqueness
DATE=$(date +%y%m%d)  # YYMMDD, e.g., 250320
TIME=$(date +%H%M%S)  # HHMMSS, e.g., 192209
SERIAL="$DATE$TIME"   # Combine for uniqueness
MAC="02:16:17:${SERIAL:0:2}:${SERIAL:2:2}:${SERIAL:4:2}"

echo "Target MAC address: $MAC"

# Show current state of eth0
echo "Current state of eth0 (before):"
ip link show eth0

# Bring interface down
echo "Bringing eth0 down..."
sudo ip link set eth0 down || { echo "Failed to bring eth0 down"; exit 1; }
sleep 2

# Unload st_gmac driver to ensure MAC can be set
echo "Unloading st_gmac driver..."
sudo modprobe -r st_gmac || { echo "Failed to unload st_gmac (check lsmod)"; exit 1; }
sleep 2

# Set the MAC address
echo "Setting new MAC address: $MAC"
sudo ip link set eth0 address "$MAC" || { echo "Failed to set MAC address"; exit 1; }

# Reload driver
echo "Reloading st_gmac driver..."
sudo modprobe st_gmac || { echo "Failed to reload st_gmac"; exit 1; }

# Bring interface back up
echo "Bringing eth0 up..."
sudo ip link set eth0 up || { echo "Failed to bring eth0 up"; exit 1; }

# Verify the change
echo "New state of eth0 (after):"
ip link show eth0

# Double-check with ethtool
echo "MAC according to ethtool:"
sudo ethtool -i eth0 | grep "bus-info" || echo "ethtool check failed"
