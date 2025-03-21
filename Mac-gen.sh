#!/bin/bash
# Get current date and time components
YEAR=$(date +%y)       # YY, e.g., 25 for 2025
MONTH=$(date +%m)      # MM, e.g., 03 for March
DAY=$(date +%d)        # DD, e.g., 20 for 20th
HOUR=$(date +%H)       # HH, e.g., 19
MINUTE=$(date +%M)     # MM, e.g., 22

# Combine month and day, then compress
MMDD="${MONTH}${DAY}"
MMDD_COMPRESSED=$(printf "%02d" $((10#${MMDD} % 100)))

# Combine hour and minute, then compress
HHMM="${HOUR}${MINUTE}"
HHMM_COMPRESSED=$(printf "%02d" $((10#${HHMM} % 100)))

# Construct the MAC address
MAC="02:16:17:${YEAR}:${MMDD_COMPRESSED}:${HHMM_COMPRESSED}"

echo "Target MAC address: $MAC"
echo "Current state of eth0 (before):"
ip link show eth0

echo "Driver info for eth0:"
ethtool -i eth0

echo "Bringing eth0 down..."
sudo ip link set eth0 down || { echo "Failed to bring eth0 down"; exit 1; }
sleep 10

echo "Setting new MAC address with ip link..."
sudo ip link set eth0 address "$MAC" || { echo "Failed to set MAC address with ip link"; exit 1; }

echo "Bringing eth0 up..."
sudo ip link set eth0 up || { echo "Failed to bring eth0 up"; exit 1; }

echo "New state of eth0 (after ip link):"
ip link show eth0

# Try ethtool as a fallback
echo "Attempting to set MAC with ethtool..."
sudo ethtool -s eth0 hwaddr "$MAC" || echo "ethtool MAC set failed (not supported or error)"

echo "State of eth0 after ethtool:"
ip link show eth0

# Make the MAC change persistent with a udev rule
echo "Creating udev rule to make MAC change persistent..."
UDEV_RULE="SUBSYSTEM==\"net\", ACTION==\"add\", ATTR{address}==\"2e:55:b5:72:43:63\", ATTR{dev_id}==\"0x0\", ATTR{type}==\"1\", RUN+=\"/sbin/ip link set dev %k address $MAC\""
UDEV_FILE="/etc/udev/rules.d/70-persistent-net.rules"
TEMP_UDEV_FILE="/tmp/70-persistent-net.rules"

# Write the udev rule to both current system and a temp location
sudo bash -c "echo '$UDEV_RULE' > $UDEV_FILE" || { echo "Failed to create udev rule in $UDEV_FILE"; exit 1; }
sudo bash -c "echo '$UDEV_RULE' > $TEMP_UDEV_FILE" || { echo "Failed to create udev rule in $TEMP_UDEV_FILE"; exit 1; }

# Reload udev rules
echo "Reloading udev rules..."
sudo udevadm control --reload-rules || { echo "Failed to reload udev rules"; exit 1; }
sudo udevadm trigger || { echo "Failed to trigger udev"; exit 1; }

# Create a post-flash script to reapply the MAC
POST_FLASH_SCRIPT="/tmp/post-flash-mac.sh"
cat << EOF > $POST_FLASH_SCRIPT
#!/bin/bash
# Reapply MAC address after flashing
MAC="$MAC"
echo "Reapplying MAC address: \$MAC"
ip link set eth0 down
sleep 5
ip link set eth0 address "\$MAC"
ip link set eth0 up
echo "New state of eth0 after post-flash script:"
ip link show eth0
# Reapply udev rule in new OS
UDEV_RULE="$UDEV_RULE"
UDEV_FILE="/etc/udev/rules.d/70-persistent-net.rules"
echo "\$UDEV_RULE" > \$UDEV_FILE
udevadm control --reload-rules
udevadm trigger
EOF

chmod +x $POST_FLASH_SCRIPT

echo "MAC change should now persist across reboots on the current system."
echo "Final state of eth0:"
ip link show eth0

echo ""
echo "IMPORTANT: After flashing the OS with ./install-aml.sh, the MAC may reset."
echo "To ensure the MAC persists in the new OS:"
echo "1. Copy the udev rule to the new OS:"
echo "   sudo cp $TEMP_UDEV_FILE /etc/udev/rules.d/70-persistent-net.rules"
echo "2. Run the post-flash script:"
echo "   sudo $POST_FLASH_SCRIPT"
echo "3. Reboot to confirm the MAC persists."