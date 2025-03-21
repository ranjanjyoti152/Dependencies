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

# Save the MAC and udev rule for post-flash use
MAC_FILE="/tmp/mac-address.txt"
UDEV_RULE="SUBSYSTEM==\"net\", ACTION==\"add\", ATTR{address}==\"2e:55:b5:72:43:63\", ATTR{dev_id}==\"0x0\", ATTR{type}==\"1\", RUN+=\"/sbin/ip link set dev %k address $MAC\""
TEMP_UDEV_FILE="/tmp/70-persistent-net.rules"

echo "$MAC" > "$MAC_FILE"
echo "$UDEV_RULE" > "$TEMP_UDEV_FILE"

# Create a post-flash script to reapply the MAC and set up persistence
POST_FLASH_SCRIPT="/tmp/post-flash-mac.sh"
cat << EOF > $POST_FLASH_SCRIPT
#!/bin/bash
# Reapply MAC address after flashing
MAC=\$(cat $MAC_FILE)
echo "Reapplying MAC address: \$MAC"
ip link set eth0 down
sleep 5
ip link set eth0 address "\$MAC"
ip link set eth0 up
echo "New state of eth0 after post-flash script:"
ip link show eth0

# Reapply udev rule in new OS
UDEV_FILE="/etc/udev/rules.d/70-persistent-net.rules"
if [ -f "$TEMP_UDEV_FILE" ]; then
    cp $TEMP_UDEV_FILE \$UDEV_FILE
    udevadm control --reload-rules
    udevadm trigger
    echo "udev rule applied to new OS."
else
    echo "Warning: $TEMP_UDEV_FILE not found. Manually apply the udev rule."
fi

# Add to rc.local or systemd service for persistence (if udev isn't enough)
RC_LOCAL="/etc/rc.local"
if [ -f "\$RC_LOCAL" ] && ! grep -q "ip link set eth0 address" "\$RC_LOCAL"; then
    sed -i -e "\$i ip link set eth0 down\nip link set eth0 address \$MAC\nip link set eth0 up\n" \$RC_LOCAL
    echo "Added MAC change to rc.local."
else
    # Fallback: Create a systemd service
    SYSTEMD_SERVICE="/etc/systemd/system/set-mac.service"
    cat << SERVICE > \$SYSTEMD_SERVICE
[Unit]
Description=Set MAC address on boot
After=network-pre.target
Before=network.target

[Service]
Type=oneshot
ExecStart=/sbin/ip link set eth0 down
ExecStart=/sbin/ip link set eth0 address $MAC
ExecStart=/sbin/ip link set eth0 up
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE
    systemctl enable set-mac.service
    echo "Created and enabled systemd service to set MAC on boot."
fi
EOF

chmod +x $POST_FLASH_SCRIPT

echo "MAC change applied to current system."
echo "Final state of eth0:"
ip link show eth0

echo ""
echo "IMPORTANT: After flashing the OS with ./install-aml.sh, the MAC may reset."
echo "To ensure the MAC persists in the new OS:"
echo "1. Before flashing, ensure $MAC_FILE and $TEMP_UDEV_FILE are copied to a persistent location (e.g., USB drive) if /tmp is wiped."
echo "2. After flashing, run the post-flash script in the new OS:"
echo "   sudo $POST_FLASH_SCRIPT"
echo "3. Reboot and verify the MAC with: ip link show eth0"