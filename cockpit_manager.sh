#!/bin/bash

# Cockpit Manager Script for Ubuntu
# This script provides options to install, remove, and update Cockpit on Ubuntu servers
# Author: ranjanjyoti152
# Date: 2025-04-26

# Colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root!${NC}"
        echo "Please run with sudo or as root user."
        exit 1
    fi
}

# Function to install Cockpit with all dependencies and features
install_cockpit() {
    echo -e "${YELLOW}Starting Cockpit installation...${NC}"
    
    # Update package lists
    echo -e "${YELLOW}Updating package lists...${NC}"
    apt update -y || { echo -e "${RED}Failed to update package lists!${NC}"; exit 1; }
    
    # Install Cockpit base package
    echo -e "${YELLOW}Installing Cockpit base package...${NC}"
    apt install -y cockpit || { echo -e "${RED}Failed to install Cockpit!${NC}"; exit 1; }
    
    # Install additional Cockpit modules for enhanced functionality
    echo -e "${YELLOW}Installing additional Cockpit modules...${NC}"
    apt install -y cockpit-pcp cockpit-packagekit cockpit-storaged cockpit-podman cockpit-machines cockpit-networkmanager || { echo -e "${RED}Warning: Some additional modules could not be installed. Continuing...${NC}"; }
    
    # Enable and start Cockpit socket service
    echo -e "${YELLOW}Enabling and starting Cockpit service...${NC}"
    systemctl enable --now cockpit.socket || { echo -e "${RED}Failed to enable Cockpit service!${NC}"; exit 1; }
    
    # Open firewall if ufw is active
    if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
        echo -e "${YELLOW}Opening firewall port for Cockpit (9090)...${NC}"
        ufw allow 9090/tcp || { echo -e "${RED}Failed to open firewall port!${NC}"; }
    fi
    
    # Check if Cockpit is running
    if systemctl is-active --quiet cockpit.socket; then
        # Get server IP for user convenience
        SERVER_IP=$(hostname -I | awk '{print $1}')
        echo -e "${GREEN}Cockpit successfully installed!${NC}"
        echo -e "${GREEN}You can access Cockpit by navigating to:${NC}"
        echo -e "${GREEN}https://$SERVER_IP:9090${NC}"
        echo -e "${GREEN}or${NC}"
        echo -e "${GREEN}https://$(hostname):9090${NC}"
    else
        echo -e "${RED}Something went wrong. Cockpit service is not running.${NC}"
        exit 1
    fi
}

# Function to remove Cockpit and its components
remove_cockpit() {
    echo -e "${YELLOW}Removing Cockpit and all its components...${NC}"
    
    # Stop and disable Cockpit service
    echo -e "${YELLOW}Stopping Cockpit service...${NC}"
    systemctl stop cockpit.socket
    systemctl disable cockpit.socket
    
    # Remove all Cockpit packages
    echo -e "${YELLOW}Removing all Cockpit packages...${NC}"
    apt remove -y cockpit cockpit-* || { echo -e "${RED}Failed to remove some Cockpit packages!${NC}"; }
    
    # Purge configurations
    echo -e "${YELLOW}Purging Cockpit configurations...${NC}"
    apt purge -y cockpit cockpit-* || { echo -e "${RED}Failed to purge some Cockpit configurations!${NC}"; }
    
    # Clean up
    echo -e "${YELLOW}Cleaning up...${NC}"
    apt autoremove -y
    
    echo -e "${GREEN}Cockpit has been successfully removed from your system.${NC}"
}

# Function to update Cockpit to the latest version
update_cockpit() {
    echo -e "${YELLOW}Updating Cockpit to the latest version...${NC}"
    
    # Update package lists
    echo -e "${YELLOW}Updating package lists...${NC}"
    apt update -y || { echo -e "${RED}Failed to update package lists!${NC}"; exit 1; }
    
    # Check if Cockpit is installed
    if ! dpkg -l | grep -q cockpit; then
        echo -e "${RED}Cockpit is not installed. Please install it first.${NC}"
        exit 1
    fi
    
    # Update Cockpit packages
    echo -e "${YELLOW}Upgrading Cockpit packages...${NC}"
    apt upgrade -y cockpit cockpit-* || { echo -e "${RED}Failed to update some Cockpit packages!${NC}"; }
    
    # Restart Cockpit service to apply changes
    echo -e "${YELLOW}Restarting Cockpit service...${NC}"
    systemctl restart cockpit.socket || { echo -e "${RED}Failed to restart Cockpit service!${NC}"; exit 1; }
    
    # Check if Cockpit is running
    if systemctl is-active --quiet cockpit.socket; then
        echo -e "${GREEN}Cockpit successfully updated!${NC}"
        # Get current installed version
        VERSION=$(dpkg -l cockpit | grep cockpit | awk '{print $3}')
        echo -e "${GREEN}Current version: $VERSION${NC}"
    else
        echo -e "${RED}Something went wrong. Cockpit service is not running after update.${NC}"
        exit 1
    fi
}

# Function to display help information
display_help() {
    echo "Cockpit Manager Script for Ubuntu"
    echo "--------------------------------"
    echo "This script allows you to install, remove, or update Cockpit on Ubuntu servers."
    echo
    echo "Usage: $0 [option]"
    echo "Options:"
    echo "  install   Install Cockpit with all dependencies and features"
    echo "  remove    Remove Cockpit completely from the system"
    echo "  update    Update Cockpit to the latest version"
    echo "  help      Display this help message"
    echo
    echo "Examples:"
    echo "  sudo $0 install"
    echo "  sudo $0 remove"
    echo "  sudo $0 update"
}

# Main script execution
check_root

# Check if an argument was provided
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: No option specified!${NC}"
    display_help
    exit 1
fi

# Process command line arguments
case "$1" in
    install)
        install_cockpit
        ;;
    remove)
        remove_cockpit
        ;;
    update)
        update_cockpit
        ;;
    help)
        display_help
        ;;
    *)
        echo -e "${RED}Error: Invalid option '$1'${NC}"
        display_help
        exit 1
        ;;
esac

exit 0