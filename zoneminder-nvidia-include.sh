#!/bin/bash

# Enable NVIDIA hardware acceleration for ZoneMinder using FFmpeg with NVENC

# Exit if any command fails
set -e

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

# Check if FFmpeg supports nvenc
echo "Checking FFmpeg for NVENC support..."
if ! ffmpeg -encoders | grep nvenc > /dev/null; then
    echo "FFmpeg does not support NVENC. Exiting."
    exit 1
fi

# Configure ZoneMinder to use FFmpeg with NVIDIA hardware acceleration
echo "Configuring ZoneMinder to use FFmpeg with NVIDIA acceleration..."

# Update the FFmpeg path in ZoneMinder's configuration file
ZM_CONFIG_FILE="/etc/zm/conf.d/01-system-paths.conf"
if grep -q "ZM_PATH_FFMPEG" "$ZM_CONFIG_FILE"; then
    sed -i 's|ZM_PATH_FFMPEG=.*|ZM_PATH_FFMPEG="/usr/bin/ffmpeg"|' "$ZM_CONFIG_FILE"
else
    echo 'ZM_PATH_FFMPEG="/usr/bin/ffmpeg"' >> "$ZM_CONFIG_FILE"
fi

# Configure the storage options in the database (using nvenc)
echo "Updating the database to use FFmpeg with NVENC encoding..."
mysql -uroot -e "UPDATE zm.Config SET Value='/usr/bin/ffmpeg' WHERE Name='ZM_PATH_FFMPEG';"

# Restart ZoneMinder service
echo "Restarting ZoneMinder service..."
service zoneminder restart

echo "NVIDIA hardware acceleration with FFmpeg NVENC for ZoneMinder is enabled!"
