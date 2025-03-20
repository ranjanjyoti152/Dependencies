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

# Check if st_gmac is loaded
echo "Checking st_gmac module status:"
lsmod | grep st_gmac || echo "st_gmac not found in lsmod"

# Bring interface down
echo "Bringing eth0 down..."
sudo ip link set eth0 down || { echo "Failed to bring eth0 down"; exit 1; }
sleep 2

# Attempt to unload st_gmac driver
echo "Unloading st_gmac driver..."
if sudo modprobe -r st_gmac; then
    echo "st_gmac unloaded successfully"
else
    echo "Failed to unload st_gmac. Checking why:"
    lsmod | grep st_gmac
    sudo lsof /dev/eth0 2>/dev/null || echo "lsof not useful here or not installed"
    exit 1
fi
sleep 2

# Set the MAC address
echo "Setting new MAC address: $MAC"
sudo ip link set eth0 address "$MAC" || { echo "Failed to set MAC address"; exit 1; }

# Reload st_gmac driver
echo "Reloading st_gmac driver..."
if sudo modprobe st_gmac; then
    echo "st_gmac reloaded successfully"
else
    echo "Failed to reload st_gmac. Check kernel modules:"
    lsmod | grep st_gmac
    exit 1
fi

# Bring interface back up
echo "Bringing eth0 up..."
sudo ip link set eth0 up || { echo "Failed to bring eth0 up"; exit 1; }

# Verify the change
echo "New state of eth0 (after):"
ip link show eth0