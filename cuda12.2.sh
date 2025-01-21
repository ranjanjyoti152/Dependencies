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

# Display welcome message
clear
cat <<EOF
##############################################################################################################
##############################                                                                              ###################################
##############################                            WELCOME TO PROXPC                                 ###################################
##############################                                                                              ###################################
##############################################################################################################
EOF

# Update and upgrade system packages
print_info "Updating system packages..."
sudo apt update && sudo apt -y upgrade
if [ $? -eq 0 ]; then
    print_success "System updated and upgraded successfully!"
else
    print_error "Failed to update system packages. Exiting script."
    exit 1
fi

# Remove unwanted NVIDIA-related packages
print_info "Removing unnecessary NVIDIA-related packages..."
sudo apt -y remove --purge "^libcuda.*" "^cuda.*" "^libnvidia.*" "^nvidia.*" "^tensorrt.*"
print_success "Unwanted NVIDIA-related packages removed!"

# Install build-essential and other necessary packages
print_info "Installing essential packages..."
sudo apt install -y build-essential gparted git net-tools openssh-server curl
if [ $? -eq 0 ]; then
    print_success "Essential packages installed successfully!"
else
    print_error "Failed to install essential packages."
    exit 1
fi

# Install SSD benchmark tool
print_info "Installing SSD benchmark tool..."
sudo snap install ssd-benchmark
print_success "SSD benchmark tool installed!"

# Set desktop wallpaper for GNOME users
if command -v gsettings &> /dev/null; then
    print_info "Setting GNOME desktop wallpaper..."
    gsettings set org.gnome.desktop.background picture-uri "https://raw.githubusercontent.com/ranjanjyoti152/opencvproxpc/main/Wallpaper-01.jpg" \
        && print_success "Wallpaper updated successfully!"
else
    print_warning "GNOME not detected. Skipping wallpaper setup."
fi

# Add NVIDIA drivers repository and install drivers
print_info "Installing NVIDIA drivers..."
sudo add-apt-repository -y ppa:graphics-drivers/ppa
sudo apt update
sudo apt install -y nvidia-driver-530
sudo dpkg --configure -a
print_success "NVIDIA drivers installed!"

# Install NVIDIA CUDA 12.2
print_info "Installing NVIDIA CUDA 12.2..."
CUDA_DEB="cuda-repo-ubuntu2204-12-2-local_12.2.0-535.54.03-1_amd64.deb"
wget -q https://developer.download.nvidia.com/compute/cuda/12.2.0/local_installers/$CUDA_DEB
sudo dpkg -i $CUDA_DEB
sudo cp /var/cuda-repo-ubuntu2204-12-2-local/cuda-*-keyring.gpg /usr/share/keyrings/
sudo apt update
sudo apt -y install cuda
print_success "NVIDIA CUDA 12.2 installed!"
rm -f $CUDA_DEB

# Install cuDNN
print_info "Installing cuDNN..."
CUDNN_DEB="cudnn-local-repo-ubuntu2004-9.3.0_1.0-1_amd64.deb"
wget -q https://developer.download.nvidia.com/compute/cudnn/9.3.0/local_installers/$CUDNN_DEB
sudo dpkg -i $CUDNN_DEB
sudo cp /var/cudnn-local-repo-ubuntu2004-9.3.0/cudnn-*-keyring.gpg /usr/share/keyrings/
sudo apt update
sudo apt -y install cudnn cudnn-cuda-12
print_success "cuDNN installed!"
rm -f $CUDNN_DEB

# Update environment variables
print_info "Updating environment variables..."
{
    echo 'export PATH=/usr/local/cuda-12.2/bin:$PATH'
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.2/lib64:$LD_LIBRARY_PATH'
} >> ~/.bashrc
source ~/.bashrc && print_success "Environment variables updated!"

# Final message
cat <<EOF
##############################################################################################################
##############################                                                                              ###################################
##############################                            INSTALLATION COMPLETE                             ###################################
##############################                       REBOOT YOUR MACHINE TO APPLY CHANGES                   ###################################
##############################################################################################################
EOF
