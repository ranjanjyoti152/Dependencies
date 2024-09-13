#!/bin/bash

# Prompt for system password once (using sudo -v to cache the password)
sudo -v

# Function definitions for printing messages
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

# Update system
print_info "Updating package list..."
if sudo apt update; then
    print_success "Package list updated successfully!"
else
    print_error "Failed to update package list. Exiting script."
    exit 1
fi

# Install build-essential
print_info "Installing build-essential..."
if sudo apt install build-essential -y; then
    print_success "build-essential installed!"
else
    print_error "Failed to install build-essential."
fi

# Check and install wget
if ! command -v wget &> /dev/null; then
    print_info "Installing wget..."
    if sudo apt-get install wget -y; then
        print_success "wget installed!"
    else
        print_error "Failed to install wget."
    fi
else
    print_info "wget is already installed."
fi

# Check and install g++
if ! command -v g++ &> /dev/null; then
    print_info "Installing C++ compiler (g++)..."
    if sudo apt-get install g++ -y; then
        print_success "g++ installed!"
    else
        print_error "Failed to install g++."
    fi
else
    print_info "g++ (C++ compiler) is already installed."
fi

# Upgrade the system
print_info "Upgrading installed packages..."
if sudo apt upgrade -y; then
    print_success "Packages upgraded!"
else
    print_error "Failed to upgrade packages."
fi

# Install JetPack only if on Jetson device
if [ -d "/usr/lib/nvidia" ]; then
    print_info "Installing NVIDIA JetPack..."
    if sudo apt-get install nvidia-jetpack -y; then
        print_success "NVIDIA JetPack installed!"
    else
        print_error "Failed to install NVIDIA JetPack."
    fi
else
    print_warning "NVIDIA JetPack can only be installed on NVIDIA Jetson devices."
fi

# Install Python3 and pip
print_info "Installing Python3 and pip..."
if sudo apt-get install -y python3 python3-pip; then
    print_success "Python3 and pip installed!"
else
    print_error "Failed to install Python3 and pip."
fi

# Install Jetson stats tool
print_info "Installing Jetson stats tool..."
if sudo pip3 install jetson-stats; then
    print_success "Jetson stats installed!"
else
    print_error "Failed to install Jetson stats tool."
fi

# Download and run swap script
print_info "Downloading swap configuration script..."
if wget https://raw.githubusercontent.com/ranjanjyoti152/nvme/main/swap.sh -q; then
    print_success "Swap script downloaded!"
else
    print_error "Failed to download swap script."
fi

# Change wallpaper if GNOME is available
if command -v gsettings &> /dev/null; then
    print_info "Setting desktop wallpaper..."
    if gsettings set org.gnome.desktop.background picture-uri https://raw.githubusercontent.com/ranjanjyoti152/opencvproxpc/main/Wallpaper-01.jpg; then
        print_success "Wallpaper set!"
    else
        print_error "Failed to set wallpaper."
    fi
else
    print_warning "GNOME not found. Skipping wallpaper setup."
fi

# Install Pi-apps
print_info "Installing Pi-apps..."
if wget -qO- https://raw.githubusercontent.com/Botspot/pi-apps/master/install | bash; then
    print_success "Pi-apps installed!"
else
    print_error "Failed to install Pi-apps."
fi

# Install RustDesk
print_info "Installing RustDesk..."
if wget -nv -O- https://raw.githubusercontent.com/ranjanjyoti152/opencvproxpc/main/Rustdesk.sh | sh -; then
    print_success "RustDesk installed!"
else
    print_error "Failed to install RustDesk."
fi

# Verify NVCC installation
print_info "Verifying NVCC installation..."
if wget -nv -O- https://raw.githubusercontent.com/ranjanjyoti152/Dependencies/main/Verify-NVCC.sh | sh -; then
    print_success "NVCC verification script executed!"
else
    print_error "Failed to execute NVCC verification script."
fi

# Compile video decoder
print_info "Running COMPILE-VIDEO-DECODER script..."
if wget -nv -O- https://raw.githubusercontent.com/ranjanjyoti152/Dependencies/refs/heads/main/COMPILE-VIDEO-DECODER.sh | sh; then
    print_success "Video decoder compilation script executed!"
else
    print_error "Failed to execute video decoder compilation script."
fi

# Make swap script executable and run it
print_info "Making swap script executable..."
if chmod +x swap.sh; then
    print_success "Swap script made executable!"
else
    print_error "Failed to make swap script executable."
fi

print_info "Running swap script..."
if sudo ./swap.sh; then
    print_success "Swap script executed!"
else
    print_error "Failed to execute swap script."
fi

# Clean up unnecessary files (ensure they exist first)
print_info "Cleaning up downloaded files..."
for file in swap.sh afterssd.sh proxpc-os-to-nvme.sh git-ssd.sh; do
    if [ -f "$file" ]; then
        sudo rm "$file" && print_success "$file removed!"
    fi
done

# Reboot the system
print_warning "System will reboot now..."
sudo reboot
