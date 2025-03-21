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
echo "Current IP address (before):"
ip addr show eth0

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

# Force IP address update with NetworkManager
echo "Forcing IP address update..."
if command -v nmcli >/dev/null 2>&1 && nmcli device status | grep -q "eth0.*ethernet.*connected"; then
    echo "NetworkManager is managing eth0."
    # Get the connection name for eth0
    CONN_NAME=$(nmcli -t -f NAME,DEVICE connection show | grep eth0 | cut -d: -f1)
    if [ -n "$CONN_NAME" ]; then
        # Modify the connection to use a new DHCP client ID based on the new MAC
        CLIENT_ID="new-client-$MAC"
        sudo nmcli connection modify "$CONN_NAME" ipv4.dhcp-client-id "$CLIENT_ID"
        echo "Set new DHCP client ID: $CLIENT_ID"

        # Clear any cached DHCP leases
        sudo rm -f /var/lib/NetworkManager/*.lease 2>/dev/null
        echo "Cleared NetworkManager DHCP lease cache."

        # Disconnect and reconnect to force a new DHCP lease
        sudo nmcli connection down "$CONN_NAME"
        sleep 2
        sudo nmcli connection up "$CONN_NAME"
        echo "NetworkManager connection restarted to renew IP."
    else
        echo "Could not find NetworkManager connection for eth0. Falling back to manual DHCP renewal..."
        sudo ip addr flush dev eth0
        if command -v dhclient >/dev/null 2>&1; then
            sudo dhclient -r eth0
            sudo dhclient eth0
            echo "Requested new DHCP lease with dhclient."
        elif command -v dhcpcd >/dev/null 2>&1; then
            sudo dhcpcd -k eth0
            sudo dhcpcd -n eth0
            echo "Requested new DHCP lease with dhcpcd."
        else
            echo "No DHCP client found. Trying to restart networking..."
            if systemctl is-active --quiet networking; then
                sudo systemctl restart networking
            else
                sudo ifdown eth0 && sudo ifup eth0
            fi
        fi
    fi
else
    echo "NetworkManager not found or not managing eth0. Using manual DHCP renewal..."
    sudo ip addr flush dev eth0
    if command -v dhclient >/dev/null 2>&1; then
        sudo dhclient -r eth0
        sudo dhclient eth0
        echo "Requested new DHCP lease with dhclient."
    elif command -v dhcpcd >/dev/null 2>&1; then
        sudo dhcpcd -k eth0
        sudo dhcpcd -n eth0
        echo "Requested new DHCP lease with dhcpcd."
    else
        echo "No DHCP client found. Trying to restart networking..."
        if systemctl is-active --quiet networking; then
            sudo systemctl restart networking
        else
            sudo ifdown eth0 && sudo ifup eth0
        fi
    fi
fi

echo "New IP address (after):"
ip addr show eth0

# Make the MAC change persistent with a udev rule
echo "Creating udev rule to make MAC change persistent..."
UDEV_RULE="SUBSYSTEM==\"net\", ACTION==\"add\", ATTR{address}==\"2e:55:b5:72:43:63\", ATTR{dev_id}==\"0x0\", ATTR{type}==\"1\", RUN+=\"/sbin/ip link set dev %k address $MAC\""
UDEV_FILE="/etc/udev/rules.d/70-persistent-net.rules"

sudo bash -c "echo '$UDEV_RULE' > $UDEV_FILE" || { echo "Failed to create udev rule in $UDEV_FILE"; exit 1; }

echo "Reloading udev rules..."
sudo udevadm control --reload-rules || { echo "Failed to reload udev rules"; exit 1; }
sudo udevadm trigger || { echo "Failed to trigger udev"; exit 1; }

# Add a systemd service for redundancy
echo "Creating systemd service to set MAC on boot..."
SYSTEMD_SERVICE="/etc/systemd/system/set-mac.service"
sudo bash -c "cat << SERVICE > $SYSTEMD_SERVICE
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
SERVICE"

sudo systemctl enable set-mac.service || { echo "Failed to enable set-mac.service"; exit 1; }

# Add a systemd service to force DHCP renewal on boot
echo "Creating systemd service to force DHCP renewal on boot..."
DHCP_SERVICE="/etc/systemd/system/force-dhcp-renewal.service"
sudo bash -c "cat << SERVICE > $DHCP_SERVICE
[Unit]
Description=Force DHCP renewal on boot
After=network-pre.target set-mac.service
Before=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/nmcli connection down \"$CONN_NAME\"
ExecStart=/usr/bin/sleep 2
ExecStart=/usr/bin/nmcli connection up \"$CONN_NAME\"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE"

sudo systemctl enable force-dhcp-renewal.service || { echo "Failed to enable force-dhcp-renewal.service"; exit 1; }

echo "MAC change applied and should persist across reboots."
echo "DHCP renewal service created to ensure new IP on reboot."
echo "Final state of eth0:"
ip link show eth0
echo "Final IP address:"
ip addr show eth0

echo ""
echo "To verify persistence:"
echo "1. Reboot the device: sudo reboot"
echo "2. Check the MAC and IP: ip addr show eth0"
echo "Note: If the IP still doesn't change on reboot, you may need to clear the DHCP lease on your router or wait for the lease to expire."