#!/bin/bash
# Get current date in YYMMDD format (e.g., 250320 for March 20, 2025)
DATE=$(date +%y%m%d)
# Use date as a pseudo-serial number
SERIAL="$DATE"
MAC="02:16:17:${SERIAL:0:2}:${SERIAL:2:2}:${SERIAL:4:2}"
echo "Setting MAC address to $MAC"
sudo ip link set eth0 address "$MAC"
