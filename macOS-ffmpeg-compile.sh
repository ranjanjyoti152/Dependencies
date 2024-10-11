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

echo -e "${CYAN}Starting FFmpeg installation process on macOS...${NC}"

# Install Homebrew if it's not installed
if ! command_exists brew; then
    echo -e "${YELLOW}Homebrew not found. Installing Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo -e "${GREEN}Homebrew is already installed.${NC}"
fi

# Install dependencies
echo -e "${CYAN}Installing dependencies using Homebrew...${NC}"
brew install automake autoconf libtool pkg-config nasm

# Clone FFmpeg source code
if [ ! -d "ffmpeg" ]; then
    echo -e "${CYAN}Cloning FFmpeg repository...${NC}"
    git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg
fi

# Change directory to ffmpeg
cd ffmpeg || { echo -e "${RED}Failed to enter ffmpeg directory.${NC}"; exit 1; }

# Configure FFmpeg
echo -e "${CYAN}Configuring FFmpeg...${NC}"
./configure

# Compile FFmpeg
echo -e "${CYAN}Compiling FFmpeg... This might take a while.${NC}"
make -j$(sysctl -n hw.ncpu)

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
