#!/bin/bash
sudo apt update
sudo apt install build-essential -y


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
echo "###############################################################################################################################################"
echo "##############################                                                                              ###################################"
echo "##############################                            WELCOME TO PROXPC                                 ###################################"
echo "##############################                                                                              ###################################"
echo "###############################################################################################################################################"

# Remove unwanted programs and clean up broken packages
print_info "Removing unwanted programs and cleaning up broken packages..."
sudo apt -y remove --purge "^libcuda.*" "^cuda.*" "^libnvidia.*" "^nvidia.*" "^tensorrt.*"
print_success "Unwanted programs removed!"

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

# Install necessary packages
print_info "Installing necessary packages..."
sudo apt install -y gparted git net-tools openssh-server curl && print_success "Necessary packages installed!"

# Install SSD benchmark tool
print_info "Installing SSD benchmark tool..."
sudo snap install ssd-benchmark && print_success "SSD benchmark tool installed!"

# Change desktop wallpaper if GNOME is available
if command -v gsettings &> /dev/null; then
    print_info "Setting desktop wallpaper..."
    gsettings set org.gnome.desktop.background picture-uri https://raw.githubusercontent.com/ranjanjyoti152/opencvproxpc/main/Wallpaper-01.jpg \
        && print_success "Wallpaper set!"
else
    print_warning "GNOME not found. Skipping wallpaper setup."
fi

# Install NVIDIA drivers
print_info "Installing NVIDIA drivers..."
sudo add-apt-repository ppa:graphics-drivers/ppa -y
sudo apt install -y nvidia-driver-530
sudo dpkg --configure -a
print_success "NVIDIA drivers installed!"

# Install NVIDIA CUDA 12.2
print_info "Installing NVIDIA CUDA 12.2..."
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin
sudo mv cuda-ubuntu2204.pin /etc/apt/preferences.d/cuda-repository-pin-600
wget https://developer.download.nvidia.com/compute/cuda/12.2.0/local_installers/cuda-repo-ubuntu2204-12-2-local_12.2.0-535.54.03-1_amd64.deb
sudo dpkg -i cuda-repo-ubuntu2204-12-2-local_12.2.0-535.54.03-1_amd64.deb
sudo cp /var/cuda-repo-ubuntu2204-12-2-local/cuda-*-keyring.gpg /usr/share/keyrings/
sudo apt-get update
sudo apt-get -y install cuda
print_success "NVIDIA CUDA 12.2 installed!"

# Install cuDNN
print_info "Installing cuDNN..."
wget https://developer.download.nvidia.com/compute/cudnn/9.3.0/local_installers/cudnn-local-repo-ubuntu2004-9.3.0_1.0-1_amd64.deb
sudo dpkg -i cudnn-local-repo-ubuntu2004-9.3.0_1.0-1_amd64.deb
sudo cp /var/cudnn-local-repo-ubuntu2004-9.3.0/cudnn-*-keyring.gpg /usr/share/keyrings/
sudo apt-get update
sudo apt-get -y install cudnn
sudo apt-get -y install cudnn-cuda-12
print_success "cuDNN installed!"

# Update environment variables
print_info "Updating environment variables..."
echo 'export PATH=/usr/local/cuda-12.2/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.2/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc && print_success "Environment variables updated!"

# Final message
echo "###############################################################################################################################################"
echo "##############################                                                                              ###################################"
echo "##############################                            INSTALLATION COMPLETE                             ###################################"
echo "##############################                       REBOOT YOUR MACHINE TO APPLY CHANGES                   ###################################"
echo "###############################################################################################################################################"
