#!/bin/bash
# Get current date and time
DATE=$(date +%y%m%d)  # YYMMDD, e.g., 250320
TIME=$(date +%H%M%S)  # HHMMSS, e.g., 143045
COUNTER="01"          # Increment this per device

# Combine into a serial
SERIAL="${DATE}${TIME}${COUNTER}"

# Extract octets using cut (portable across shells)
OCTET1=$(echo "$SERIAL" | cut -c 1-2)  # First 2 chars
OCTET2=$(echo "$SERIAL" | cut -c 3-4)  # Next 2 chars
OCTET3=$(echo "$SERIAL" | cut -c 5-6)  # Next 2 chars

# Construct the MAC address
MAC="02:16:17:$OCTET1:$OCTET2:$OCTET3"

echo "Setting MAC address to $MAC"
sudo ip link set eth0 address "$MAC"
