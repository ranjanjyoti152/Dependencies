#!/bin/bash

# Script to automate the setup of RM520N-GL modem on Jetson device
# Run this as root or with sudo privileges

# Step 1: Prepare the Jetson Device

echo "Starting setup for RM520N-GL modem..."

# Step 2: Remove default Modem Manager
echo "Removing default modem manager..."
sudo apt-get remove --purge modemmanager -y
sudo apt autoremove -y

# Step 3: Download and install drivers
echo "Downloading necessary drivers..."
wget https://raw.githubusercontent.com/ranjanjyoti152/Dependencies/main/pcie_mhi.zip
wget https://raw.githubusercontent.com/ranjanjyoti152/Dependencies/main/qmi_wwan_q.zip

echo "Unzipping driver files..."
unzip pcie_mhi.zip
unzip qmi_wwan_q.zip

# Step 4: Install the drivers
echo "Installing PCIe MHI driver..."
cd pcie_mhi
make
sudo make install

# Go back to the home directory
cd ~

echo "Installing QMI WWAN driver..."
cd qmi_wwan_q
make
sudo make install

# Go back to the home directory again
cd ~

# Step 5: Install Minicom for modem communication
echo "Installing Minicom..."
sudo apt update -y
sudo apt install minicom -y

# Step 6: Configure Minicom
echo "Configuring Minicom..."
sudo minicom -s



# Step 8: Check for network connectivity
echo "Checking for network connectivity..."
ip addr show usb0 || ip addr show usb1

# Step 9: Setup automatic connection on startup
echo "Setting up automatic network connection on restart..."
wget https://raw.githubusercontent.com/ranjanjyoti152/Dependencies/main/modem.sh
chmod +x modem.sh

# Add script to crontab for auto-start
echo "Adding modem.sh to crontab..."
(crontab -l 2>/dev/null; echo "@reboot /home/proxpc/modem.sh") | crontab -

# Step 10: Allow minicom to run without a password
echo "Configuring sudoers to allow minicom without a password..."
sudo sed -i '/minicom/d' /etc/sudoers
echo "proxpc ALL=(ALL) NOPASSWD: /usr/bin/minicom" | sudo tee -a /etc/sudoers

echo "Setup complete. Please reboot your device manually to apply all changes."
