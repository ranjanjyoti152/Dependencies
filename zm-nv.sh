#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Start FFmpeg installation process
echo -e "${CYAN}Starting FFmpeg installation with NVIDIA NVENC support on Ubuntu...${NC}"

# Update and install dependencies
echo -e "${CYAN}Updating package list and installing dependencies...${NC}"
sudo apt update

# Check architecture
ARCH=$(uname -m)
echo -e "${CYAN}Detected architecture: ${ARCH}${NC}"

# Install common dependencies
if [[ "$ARCH" == "x86_64" ]]; then
    echo -e "${CYAN}Detected Intel/AMD 64-bit architecture.${NC}"
    sudo apt install -y automake autoconf libtool pkg-config nasm yasm \
                        libx264-dev libx265-dev libvpx-dev libfdk-aac-dev \
                        libmp3lame-dev libopus-dev

elif [[ "$ARCH" == "aarch64" ]]; then
    echo -e "${CYAN}Detected ARM 64-bit architecture (aarch64).${NC}"
    sudo apt install -y automake autoconf libtool pkg-config nasm yasm \
                        libx264-dev libx265-dev libvpx-dev libfdk-aac-dev \
                        libmp3lame-dev libopus-dev
else
    echo -e "${RED}Unsupported architecture: $ARCH${NC}"
    exit 1
fi

# Install CUDA and NVIDIA headers for NVENC
echo -e "${CYAN}Installing CUDA and NVIDIA headers for NVENC support...${NC}"
sudo apt install -y nvidia-cuda-toolkit

# Download and install NVENC headers if not already installed
if [ ! -d "nv-codec-headers" ]; then
    echo -e "${CYAN}Cloning NVIDIA NVENC headers...${NC}"
    git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git
    cd nv-codec-headers || { echo -e "${RED}Failed to enter nv-codec-headers directory.${NC}"; exit 1; }
    sudo make install
    cd ..
fi

# Clone FFmpeg source code
if [ ! -d "ffmpeg" ]; then
    echo -e "${CYAN}Cloning FFmpeg repository...${NC}"
    git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg
fi

# Change directory to ffmpeg
cd ffmpeg || { echo -e "${RED}Failed to enter ffmpeg directory.${NC}"; exit 1; }

# Configure FFmpeg with NVENC and necessary flags
echo -e "${CYAN}Configuring FFmpeg with NVIDIA NVENC support...${NC}"
./configure --enable-gpl --enable-nonfree --enable-libx264 --enable-libx265 \
            --enable-libvpx --enable-libfdk-aac --enable-libmp3lame --enable-libopus \
            --enable-cuda --enable-nvenc --enable-cuvid --enable-libnpp \
            --extra-cflags=-I/usr/local/cuda/include --extra-ldflags=-L/usr/local/cuda/lib64

# Compile FFmpeg
echo -e "${CYAN}Compiling FFmpeg... This might take a while.${NC}"
make -j$(nproc)

# Install FFmpeg
echo -e "${CYAN}Installing FFmpeg...${NC}"
sudo make install

# Verify installation of FFmpeg with NVENC
if command_exists ffmpeg; then
    echo -e "${GREEN}FFmpeg installed successfully!${NC}"
    ffmpeg -version

    # Verify NVENC support
    if ffmpeg -encoders | grep nvenc > /dev/null; then
        echo -e "${GREEN}FFmpeg supports NVIDIA NVENC!${NC}"
    else
        echo -e "${RED}FFmpeg does not support NVIDIA NVENC. Please check the installation steps.${NC}"
        exit 1
    fi
else
    echo -e "${RED}FFmpeg installation failed.${NC}"
    exit 1
fi

# Now configure ZoneMinder to use FFmpeg with NVENC

# Update ZoneMinder configuration file to use FFmpeg
ZM_CONFIG_FILE="/etc/zm/conf.d/01-system-paths.conf"
echo -e "${CYAN}Configuring ZoneMinder to use FFmpeg with NVIDIA NVENC...${NC}"

if grep -q "ZM_PATH_FFMPEG" "$ZM_CONFIG_FILE"; then
    sudo sed -i 's|ZM_PATH_FFMPEG=.*|ZM_PATH_FFMPEG="/usr/bin/ffmpeg"|' "$ZM_CONFIG_FILE"
else
    echo 'ZM_PATH_FFMPEG="/usr/bin/ffmpeg"' | sudo tee -a "$ZM_CONFIG_FILE"
fi

# Update ZoneMinder database to use FFmpeg
echo -e "${CYAN}Updating ZoneMinder database with FFmpeg path...${NC}"
mysql -uroot -e "UPDATE zm.Config SET Value='/usr/bin/ffmpeg' WHERE Name='ZM_PATH_FFMPEG';"

# Restart ZoneMinder service
echo -e "${CYAN}Restarting ZoneMinder service...${NC}"
sudo service zoneminder restart

echo -e "${GREEN}NVIDIA NVENC hardware acceleration for ZoneMinder is enabled!${NC}"
