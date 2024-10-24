#!/bin/bash

# Enable ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Function to display colored messages
function echo_color {
    echo -e "${1}${2}${RESET}"
}

echo_color $CYAN "Checking dependencies..."

# Check if yasm is installed
if ! command -v yasm &> /dev/null
then
    echo_color $RED "Yasm not found! Installing..."
    pacman -S --noconfirm yasm
    if [ $? -ne 0 ]; then
        echo_color $RED "Failed to install Yasm!"
        exit 1
    fi
else
    echo_color $GREEN "Yasm found!"
fi

# Check if nasm is installed
if ! command -v nasm &> /dev/null
then
    echo_color $RED "Nasm not found! Installing..."
    pacman -S --noconfirm nasm
    if [ $? -ne 0 ]; then
        echo_color $RED "Failed to install Nasm!"
        exit 1
    fi
else
    echo_color $GREEN "Nasm found!"
fi

# Check if Git is installed
if ! command -v git &> /dev/null
then
    echo_color $RED "Git not found! Installing..."
    pacman -S --noconfirm git
    if [ $? -ne 0 ]; then
        echo_color $RED "Failed to install Git!"
        exit 1
    fi
else
    echo_color $GREEN "Git found!"
fi

# Clone FFmpeg repository
echo_color $CYAN "Cloning FFmpeg repository..."
if [ ! -d "ffmpeg" ]; then
    git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg
    if [ $? -ne 0 ]; then
        echo_color $RED "Failed to clone FFmpeg repository!"
        exit 1
    fi
else
    echo_color $YELLOW "FFmpeg repository already exists. Skipping clone."
fi

# Change directory to ffmpeg
cd ffmpeg || { echo_color $RED "Failed to change directory to ffmpeg!"; exit 1; }

# Configure FFmpeg
echo_color $CYAN "Configuring FFmpeg..."
./configure
if [ $? -ne 0 ]; then
    echo_color $RED "FFmpeg configuration failed!"
    exit 1
fi

# Compile FFmpeg
echo_color $CYAN "Compiling FFmpeg..."
make -j$(nproc)
if [ $? -ne 0 ]; then
    echo_color $RED "FFmpeg compilation failed!"
    exit 1
else
    echo_color $GREEN "FFmpeg compiled successfully!"
fi

echo_color $GREEN "All done! FFmpeg is ready to use!"
