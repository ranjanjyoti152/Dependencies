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

print_info "Updating package list..."
sudo apt update && print_success "Package list updated!"

print_info "Upgrading installed packages..."
sudo apt upgrade -y && print_success "Packages upgraded!"

print_info "Installing NVIDIA JetPack..."
sudo apt-get install nvidia-jetpack -y && print_success "NVIDIA JetPack installed!"

print_info "Installing Python3 and pip..."
sudo apt-get -y install python3-pip && print_success "Python3 and pip installed!"

print_info "Installing Jetson stats tool..."
sudo pip3 install jetson-stats && print_success "Jetson stats installed!"

print_info "Downloading swap configuration script..."
wget https://raw.githubusercontent.com/ranjanjyoti152/nvme/main/swap.sh -q && print_success "Swap script downloaded!"

print_info "Setting desktop wallpaper..."
gsettings set org.gnome.desktop.background picture-uri https://raw.githubusercontent.com/ranjanjyoti152/opencvproxpc/main/Wallpaper-01.jpg \
    && print_success "Wallpaper set!"

print_info "Installing Pi-apps..."
wget -qO- https://raw.githubusercontent.com/Botspot/pi-apps/master/install | bash && print_success "Pi-apps installed!"

print_info "Installing RustDesk..."
wget -nv -O- https://raw.githubusercontent.com/ranjanjyoti152/opencvproxpc/main/Rustdesk.sh | sh - \
    && print_success "RustDesk installed!"

print_info "Verifying NVCC installation..."
wget -nv -O- https://raw.githubusercontent.com/ranjanjyoti152/Dependencies/main/Verify-NVCC.sh | sh - \
    && print_success "NVCC verification script executed!"

print_info "Making swap script executable..."
chmod +x swap.sh && print_success "Swap script made executable!"

print_info "Running swap script..."
sudo ./swap.sh && print_success "Swap script executed!"

print_info "Cleaning up downloaded files..."
sudo rm swap.sh afterssd.sh proxpc-os-to-nvme.sh git-ssd.sh \
    && print_success "Cleanup completed!"

print_warning "System will reboot now..."
sudo reboot
