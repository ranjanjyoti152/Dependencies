#!/bin/bash

# Function to print colored messages
print_info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

print_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

# Check if wget is installed
if ! command -v wget &> /dev/null; then
    print_info "Installing wget..."
    sudo apt-get install wget -y && print_success "wget installed!"
else
    print_info "wget is already installed."
fi

# Check if g++ (C++ compiler) is installed
if ! command -v g++ &> /dev/null; then
    print_info "Installing C++ compiler (g++)..."
    sudo apt-get install g++ -y && print_success "g++ installed!"
else
    print_info "g++ (C++ compiler) is already installed."
fi

# Update and upgrade the system
print_info "Updating package list..."
sudo apt update
if [ $? -ne 0 ]; then
    print_error "Failed to update package list. Exiting script."
    exit 1
else
    print_success "Package list updated successfully!"
fi

print_info "Upgrading installed packages..."
sudo apt upgrade -y && print_success "Packages upgraded!"

# Install JetPack only if on Jetson device
if [ -d "/usr/lib/nvidia" ]; then
    print_info "Installing NVIDIA JetPack..."
    sudo apt-get install nvidia-jetpack -y && print_success "NVIDIA JetPack installed!"
else
    print_warning "NVIDIA JetPack can only be installed on NVIDIA Jetson devices."
fi

# Install Python3 and pip
print_info "Installing Python3 and pip..."
sudo apt-get install -y python3 python3-pip && print_success "Python3 and pip installed!"

# Install Jetson stats tool
print_info "Installing Jetson stats tool..."
sudo pip3 install jetson-stats && print_success "Jetson stats installed!"

# Download and run swap script
print_info "Downloading swap configuration script..."
wget https://raw.githubusercontent.com/ranjanjyoti152/nvme/main/swap.sh -q && print_success "Swap script downloaded!"

# Change wallpaper if GNOME is available
if command -v gsettings &> /dev/null; then
    print_info "Setting desktop wallpaper..."
    gsettings set org.gnome.desktop.background picture-uri https://raw.githubusercontent.com/ranjanjyoti152/opencvproxpc/main/Wallpaper-01.jpg \
        && print_success "Wallpaper set!"
else
    print_warning "GNOME not found. Skipping wallpaper setup."
fi

# Install Pi-apps
print_info "Installing Pi-apps..."
wget -qO- https://raw.githubusercontent.com/Botspot/pi-apps/master/install | bash && print_success "Pi-apps installed!"

# Install RustDesk
print_info "Installing RustDesk..."
wget -nv -O- https://raw.githubusercontent.com/ranjanjyoti152/opencvproxpc/main/Rustdesk.sh | sh - \
    && print_success "RustDesk installed!"

# Verify NVCC installation
print_info "Verifying NVCC installation..."
wget -nv -O- https://raw.githubusercontent.com/ranjanjyoti152/Dependencies/main/Verify-NVCC.sh | sh - \
    && print_success "NVCC verification script executed!"

# Make swap script executable and run it
print_info "Making swap script executable..."
chmod +x swap.sh && print_success "Swap script made executable!"

print_info "Running swap script..."
sudo ./swap.sh && print_success "Swap script executed!"

# Clean up unnecessary files
print_info "Cleaning up downloaded files..."
sudo rm swap.sh afterssd.sh proxpc-os-to-nvme.sh git-ssd.sh \
    && print_success "Cleanup completed!"

# Reboot the system
print_warning "System will reboot now..."
sudo reboot
