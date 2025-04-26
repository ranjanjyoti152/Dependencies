#!/bin/bash

# Cockpit Manager Script for Ubuntu
# Includes GPU utilization monitoring and GPU passthrough for VMs
# Author: ranjanjyoti152add
# Date: 2025-04-26 03:18:55

# Colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if script is run as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root!${NC}"
        echo "Please run with sudo or as root user."
        exit 1
    fi
}

# Function to check if a package exists in repos
package_exists() {
    apt-cache show "$1" &>/dev/null
    return $?
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
    
    # Install all official Cockpit modules available in the repositories
    echo -e "${YELLOW}Installing available official Cockpit modules...${NC}"
    
    # Core modules most likely to be available in Ubuntu
    CORE_MODULES="cockpit-pcp cockpit-packagekit cockpit-storaged cockpit-podman cockpit-networkmanager cockpit-system cockpit-ws cockpit-bridge"
    apt install -y $CORE_MODULES || { echo -e "${YELLOW}Warning: Some core modules could not be installed. Continuing...${NC}"; }
    
    # Additional modules that might not be available in all Ubuntu versions
    echo -e "${YELLOW}Checking for additional Cockpit modules...${NC}"
    ADDITIONAL_MODULES=""
    
    # Check each module individually
    for module in cockpit-machines cockpit-sosreport cockpit-389-ds cockpit-navigator cockpit-certificate cockpit-file-sharing cockpit-ostree; do
        if package_exists "$module"; then
            ADDITIONAL_MODULES="$ADDITIONAL_MODULES $module"
        else
            echo -e "${YELLOW}Module $module is not available in your repositories. Skipping...${NC}"
        fi
    done
    
    # Install additional modules if any are available
    if [ -n "$ADDITIONAL_MODULES" ]; then
        echo -e "${YELLOW}Installing additional available Cockpit modules...${NC}"
        apt install -y $ADDITIONAL_MODULES || { echo -e "${YELLOW}Warning: Some additional modules could not be installed. Continuing...${NC}"; }
    fi
    
    # Install GPU monitoring and passthrough capabilities
    install_gpu_support
    
    # Enable and start Cockpit socket service
    echo -e "${YELLOW}Enabling and starting Cockpit service...${NC}"
    systemctl enable --now cockpit.socket || { echo -e "${RED}Failed to enable Cockpit service!${NC}"; exit 1; }
    
    # Open firewall if ufw is active
    if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
        echo -e "${YELLOW}Opening firewall port for Cockpit (9090)...${NC}"
        ufw allow 9090/tcp || { echo -e "${RED}Failed to open firewall port!${NC}"; }
    fi
    
    # Display installed Cockpit modules
    echo -e "${GREEN}Installed Cockpit modules:${NC}"
    dpkg -l | grep cockpit | awk '{print "- " $2}' | sort
    
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

# Function to install GPU support for monitoring and passthrough
install_gpu_support() {
    echo -e "${BLUE}Setting up GPU monitoring and passthrough capabilities...${NC}"
    
    # Check for NVIDIA GPUs
    if lspci | grep -i nvidia > /dev/null; then
        echo -e "${YELLOW}NVIDIA GPU detected. Installing NVIDIA monitoring tools...${NC}"
        
        # Install NVIDIA driver and tools if not already installed
        if ! command -v nvidia-smi &> /dev/null; then
            echo -e "${YELLOW}Installing NVIDIA drivers and tools...${NC}"
            apt install -y nvidia-utils-* nvidia-driver-* || { echo -e "${RED}Failed to install NVIDIA drivers. You might need to install them manually.${NC}"; }
        fi
        
        # Install NVTOP for GPU monitoring
        if ! package_exists "nvtop"; then
            echo -e "${YELLOW}Adding universe repository for NVTOP...${NC}"
            add-apt-repository -y universe
            apt update -y
        fi
        
        echo -e "${YELLOW}Installing NVTOP for GPU monitoring...${NC}"
        apt install -y nvtop || { echo -e "${RED}Failed to install NVTOP.${NC}"; }
        
        # Install Performance Co-Pilot NVIDIA plugin for Cockpit integration
        echo -e "${YELLOW}Installing PCP NVIDIA PMDA for Cockpit integration...${NC}"
        apt install -y pcp-pmda-nvidia || { echo -e "${YELLOW}PCP NVIDIA PMDA not available, GPU metrics may not appear in Cockpit.${NC}"; }
        
        # Enable the NVIDIA PMDA if installed
        if [ -f /var/lib/pcp/pmdas/nvidia/Install ]; then
            echo -e "${YELLOW}Enabling PCP NVIDIA metrics collection...${NC}"
            cd /var/lib/pcp/pmdas/nvidia && ./Install
        fi
    fi
    
    # Check for AMD GPUs
    if lspci | grep -i amd > /dev/null || lspci | grep -i radeon > /dev/null; then
        echo -e "${YELLOW}AMD GPU detected. Installing AMD monitoring tools...${NC}"
        
        # Install AMD driver and tools
        apt install -y radeontop || { echo -e "${RED}Failed to install AMD monitoring tools.${NC}"; }
        
        # Install Performance Co-Pilot AMD plugin if available
        apt install -y pcp-pmda-amdgpu || { echo -e "${YELLOW}PCP AMD GPU PMDA not available, GPU metrics may not appear in Cockpit.${NC}"; }
        
        # Enable the AMD GPU PMDA if installed
        if [ -f /var/lib/pcp/pmdas/amdgpu/Install ]; then
            echo -e "${YELLOW}Enabling PCP AMD GPU metrics collection...${NC}"
            cd /var/lib/pcp/pmdas/amdgpu && ./Install
        fi
    fi
    
    # Setup for GPU passthrough to VMs
    echo -e "${BLUE}Setting up GPU passthrough for virtual machines...${NC}"
    
    # Check if virtualization is supported
    if ! grep -E 'vmx|svm' /proc/cpuinfo > /dev/null; then
        echo -e "${RED}CPU virtualization not detected. GPU passthrough may not work.${NC}"
    else
        # Install required virtualization packages
        echo -e "${YELLOW}Installing virtualization requirements for GPU passthrough...${NC}"
        apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager || { echo -e "${RED}Failed to install some virtualization packages.${NC}"; }
        
        # Enable IOMMU in GRUB if not already enabled
        if ! grep -q "intel_iommu=on" /etc/default/grub && ! grep -q "amd_iommu=on" /etc/default/grub; then
            echo -e "${YELLOW}Enabling IOMMU in GRUB configuration...${NC}"
            
            # Detect CPU vendor for correct IOMMU parameter
            if grep -q "GenuineIntel" /proc/cpuinfo; then
                IOMMU_PARAM="intel_iommu=on iommu=pt"
            else
                IOMMU_PARAM="amd_iommu=on iommu=pt"
            fi
            
            # Update GRUB command line
            sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$IOMMU_PARAM /" /etc/default/grub
            update-grub
            
            echo -e "${YELLOW}IOMMU has been enabled. A system reboot will be required for GPU passthrough to work.${NC}"
        fi
        
        # Configure VFIO if needed
        if ! grep -q "vfio" /etc/modules; then
            echo -e "${YELLOW}Configuring VFIO kernel modules...${NC}"
            cat >> /etc/modules << EOF
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
EOF
            
            # Create modprobe config for VFIO
            cat > /etc/modprobe.d/vfio.conf << EOF
options vfio-pci ids=
softdep nvidia pre: vfio-pci
softdep amdgpu pre: vfio-pci
EOF
            echo -e "${YELLOW}VFIO modules configured. You'll need to add your GPU's vendor and device IDs to enable full passthrough.${NC}"
            echo -e "${YELLOW}You can use 'lspci -nn' to identify your GPU's IDs.${NC}"
        fi
        
        # Enable nested virtualization if on an Intel CPU
        if grep -q "GenuineIntel" /proc/cpuinfo; then
            echo -e "${YELLOW}Enabling nested virtualization for Intel CPUs...${NC}"
            if [ ! -f /etc/modprobe.d/kvm-intel.conf ]; then
                echo "options kvm-intel nested=1" > /etc/modprobe.d/kvm-intel.conf
                echo -e "${YELLOW}Nested virtualization enabled for Intel CPU.${NC}"
            fi
        fi
        
        # Enable nested virtualization if on an AMD CPU
        if grep -q "AuthenticAMD" /proc/cpuinfo; then
            echo -e "${YELLOW}Enabling nested virtualization for AMD CPUs...${NC}"
            if [ ! -f /etc/modprobe.d/kvm-amd.conf ]; then
                echo "options kvm-amd nested=1" > /etc/modprobe.d/kvm-amd.conf
                echo -e "${YELLOW}Nested virtualization enabled for AMD CPU.${NC}"
            fi
        fi
    fi
    
    # Install Cockpit machines module if available
    if ! dpkg -l | grep -q cockpit-machines; then
        echo -e "${YELLOW}Installing Cockpit VM management module...${NC}"
        apt install -y cockpit-machines || { echo -e "${RED}Failed to install Cockpit VM management module.${NC}"; }
    fi
    
    echo -e "${GREEN}GPU support setup complete.${NC}"
    echo -e "${YELLOW}Note: A system reboot may be required for some changes to take effect.${NC}"
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
    
    # Remove GPU monitoring tools
    echo -e "${YELLOW}Removing GPU monitoring tools...${NC}"
    apt remove -y nvtop radeontop pcp-pmda-nvidia pcp-pmda-amdgpu || { echo -e "${YELLOW}Some GPU tools could not be removed or were not installed.${NC}"; }
    
    # Clean up
    echo -e "${YELLOW}Cleaning up...${NC}"
    apt autoremove -y
    
    echo -e "${GREEN}Cockpit and related components have been successfully removed from your system.${NC}"
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
    
    # Update GPU monitoring tools
    echo -e "${YELLOW}Updating GPU monitoring tools...${NC}"
    apt upgrade -y nvtop radeontop pcp-pmda-nvidia pcp-pmda-amdgpu || { echo -e "${YELLOW}Some GPU tools could not be updated or are not installed.${NC}"; }
    
    # Restart Cockpit service to apply changes
    echo -e "${YELLOW}Restarting Cockpit service...${NC}"
    systemctl restart cockpit.socket || { echo -e "${RED}Failed to restart Cockpit service!${NC}"; exit 1; }
    
    # Restart PCP service to apply GPU monitoring changes
    if systemctl is-active --quiet pmcd; then
        echo -e "${YELLOW}Restarting Performance Co-Pilot service...${NC}"
        systemctl restart pmcd
    fi
    
    # Display updated Cockpit modules
    echo -e "${GREEN}Installed Cockpit modules:${NC}"
    dpkg -l | grep cockpit | awk '{print "- " $2 " (version: " $3 ")"}' | sort
    
    # Check if Cockpit is running
    if systemctl is-active --quiet cockpit.socket; then
        echo -e "${GREEN}Cockpit successfully updated!${NC}"
    else
        echo -e "${RED}Something went wrong. Cockpit service is not running after update.${NC}"
        exit 1
    fi
}

# Function to display help information
display_help() {
    echo "Cockpit Manager Script for Ubuntu"
    echo "--------------------------------"
    echo "This script provides options to install, remove, or update Cockpit on Ubuntu servers."
    echo "Includes GPU monitoring and passthrough capabilities for virtual machines."
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

# Function to provide interactive menu
interactive_menu() {
    echo "=== Cockpit Manager for Ubuntu ==="
    echo "Please select an option:"
    echo "1) Install Cockpit with GPU support"
    echo "2) Remove Cockpit"
    echo "3) Update Cockpit"
    echo "4) Exit"
    echo
    
    read -p "Enter your choice [1-4]: " choice
    
    case $choice in
        1)
            install_cockpit
            ;;
        2)
            remove_cockpit
            ;;
        3)
            update_cockpit
            ;;
        4)
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please try again.${NC}"
            exit 1
            ;;
    esac
}

# Process the combined command format (username + action)
parse_combined_command() {
    local input="$1"
    
    if [[ "$input" == *"install"* ]]; then
        echo "install"
    elif [[ "$input" == *"remove"* ]]; then
        echo "remove"
    elif [[ "$input" == *"update"* ]]; then
        echo "update"
    else
        echo "unknown"
    fi
}

# Main script execution
check_root

# Detect if we're being piped through wget or similar
if [ "$0" = "sh" ] || [ "$0" = "bash" ] || [ "$0" = "-" ]; then
    # Handle the specific format used in the command
    if [[ "$1" == *"install"* || "$1" == *"remove"* || "$1" == *"update"* ]]; then
        action=$(parse_combined_command "$1")
        case "$action" in
            install)
                install_cockpit
                ;;
            remove)
                remove_cockpit
                ;;
            update)
                update_cockpit
                ;;
            *)
                echo -e "${RED}Error: Invalid option in command '$1'${NC}"
                display_help
                exit 1
                ;;
        esac
        exit 0
    fi
fi

# First argument is the script name when piped through sh
# Shift to get the actual first argument
if [ "$1" = "sh" ] || [ "$1" = "bash" ] || [ "$1" = "-" ]; then
    shift
fi

# Process command line arguments
if [ $# -eq 0 ]; then
    # No arguments provided, show interactive menu
    interactive_menu
else
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
            # Check if this might be a combined username+command
            action=$(parse_combined_command "$1")
            if [ "$action" != "unknown" ]; then
                case "$action" in
                    install)
                        install_cockpit
                        ;;
                    remove)
                        remove_cockpit
                        ;;
                    update)
                        update_cockpit
                        ;;
                esac
            else
                echo -e "${RED}Error: Invalid option '$1'${NC}"
                display_help
                exit 1
            fi
            ;;
    esac
fi

exit 0