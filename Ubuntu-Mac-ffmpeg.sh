#!/bin/bash

# Define colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo -e "${CYAN}Starting FFmpeg installation process on Ubuntu...${NC}"

# Update and install dependencies
echo -e "${CYAN}Updating package list and installing dependencies...${NC}"
sudo apt update

# Check the architecture
ARCH=$(uname -m)
echo -e "${CYAN}Detected architecture: ${ARCH}${NC}"

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

# Clone FFmpeg source code
if [ ! -d "ffmpeg" ]; then
    echo -e "${CYAN}Cloning FFmpeg repository...${NC}"
    git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg
fi

# Change directory to ffmpeg
cd ffmpeg || { echo -e "${RED}Failed to enter ffmpeg directory.${NC}"; exit 1; }

# Configure FFmpeg with necessary flags
echo -e "${CYAN}Configuring FFmpeg...${NC}"
./configure --enable-gpl --enable-nonfree --enable-libx264 --enable-libx265 \
            --enable-libvpx --enable-libfdk-aac --enable-libmp3lame --enable-libopus

# Compile FFmpeg
echo -e "${CYAN}Compiling FFmpeg... This might take a while.${NC}"
make -j$(nproc)

# Install FFmpeg
echo -e "${CYAN}Installing FFmpeg...${NC}"
sudo make install

# Verify installation
if command_exists ffmpeg; then
    echo -e "${GREEN}FFmpeg installed successfully!${NC}"
    ffmpeg -version
else
    echo -e "${RED}FFmpeg installation failed.${NC}"
fi
