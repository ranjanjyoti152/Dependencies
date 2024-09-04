#!/bin/bash

# Set a custom password
rustdesk_pw="Prox@123"

# Get your config string from your Web portal and Fill Below
rustdesk_cfg="secure-string"

################################### Please Do Not Edit Below This Line #########################################

# Check if the script is being run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# Identify OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID

    UPSTREAM_ID=${ID_LIKE,,}

    if [ "${UPSTREAM_ID}" != "debian" ] && [ "${UPSTREAM_ID}" != "ubuntu" ]; then
        UPSTREAM_ID="$(echo ${ID_LIKE,,} | sed s/\"//g | cut -d' ' -f1)"
    fi

elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSE-release ]; then
    OS=SuSE
    VER=$(cat /etc/SuSE-release)
elif [ -f /etc/redhat-release ]; then
    OS=RedHat
    VER=$(cat /etc/redhat-release)
else
    OS=$(uname -s)
    VER=$(uname -r)
fi

# Checks the latest version of RustDesk
RDLATEST=$(curl https://api.github.com/repos/rustdesk/rustdesk/releases/latest -s | grep "tag_name" | awk -F'"' '{print $4}')

# Install RustDesk

echo "Installing RustDesk"
if [ "${ID}" = "debian" ] || [ "$OS" = "Ubuntu" ] || [ "$OS" = "Debian" ] || [ "${UPSTREAM_ID}" = "ubuntu" ] || [ "${UPSTREAM_ID}" = "debian" ]; then
    wget https://github.com/rustdesk/rustdesk/releases/download/${RDLATEST}/rustdesk-${RDLATEST}-x86_64.deb
    apt-get install -fy ./rustdesk-${RDLATEST}-x86_64.deb >/dev/null
elif [ "$OS" = "CentOS" ] || [ "$OS" = "RedHat" ] || [ "$OS" = "Fedora Linux" ] || [ "${UPSTREAM_ID}" = "rhel" ]; then
    wget https://github.com/rustdesk/rustdesk/releases/download/${RDLATEST}/rustdesk-${RDLATEST}.x86_64.rpm
    yum localinstall ./rustdesk-${RDLATEST}.x86_64.rpm -y >/dev/null
elif [ "${UPSTREAM_ID}" = "suse" ]; then
    wget https://github.com/rustdesk/rustdesk/releases/download/${RDLATEST}/rustdesk-${RDLATEST}.x86_64-suse.rpm
    zypper -n install --allow-unsigned-rpm ./rustdesk-${RDLATEST}.x86_64-suse.rpm >/dev/null
else
    echo "Unsupported OS"
    exit 1
fi

# Ensure RustDesk directories exist for the root and user profiles
mkdir -p /home/${SUDO_USER}/.config/rustdesk
mkdir -p /root/.config/rustdesk

# Set the custom password permanently
rustdesk --password ${rustdesk_pw}

# Kill any existing RustDesk processes
sudo pkill -f "rustdesk"

# Setup RustDesk in the user profile
rustdesktoml2a="$(cat << EOF
rendezvous_server = '122.187.43.226'
nat_type = 1
serial = 3
[options]
rendezvous-servers = 'rs-ny.rustdesk.com,rs-sg.rustdesk.com,rs-cn.rustdesk.com'
key = 'x+aLnDBZOIYjUmpiJYczxshbHqKOUExojrfaCby5AD4='
custom-rendezvous-server = '122.187.43.226'
api-server = 'https://122.187.43.226'
relay-server = '122.187.43.226'
EOF
)"
echo "${rustdesktoml2a}" | sudo tee /home/${SUDO_USER}/.config/rustdesk/RustDesk2.toml > /dev/null

# Setup RustDesk in the root profile
rustdesktoml2b="$(cat << EOF
rendezvous_server = '122.187.43.226'
nat_type = 1
serial = 3
[options]
rendezvous-servers = 'rs-ny.rustdesk.com,rs-sg.rustdesk.com,rs-cn.rustdesk.com'
key = 'x+aLnDBZOIYjUmpiJYczxshbHqKOUExojrfaCby5AD4='
custom-rendezvous-server = '122.187.43.226'
api-server = 'https://122.187.43.226'
relay-server = '122.187.43.226'
EOF
)"
echo "${rustdesktoml2b}" | sudo tee /root/.config/rustdesk/RustDesk2.toml > /dev/null

# Restart the RustDesk service
systemctl restart rustdesk

# Verify that RustDesk is running and check for errors
if systemctl is-active --quiet rustdesk; then
    echo "RustDesk service is running successfully."
else
    echo "RustDesk service failed to start. Please check the service logs for more information."
fi

echo "All done! Please double check the Network settings tab in RustDesk."
echo ""
echo "..............................................."
if [ -n "$rustdesk_id" ]; then
    echo "RustDesk ID: $rustdesk_id"
else
    echo "Failed to get RustDesk ID."
fi

echo "Password: $rustdesk_pw"
echo "..............................................."
