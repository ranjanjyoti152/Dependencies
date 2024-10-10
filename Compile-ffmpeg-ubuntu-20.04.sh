#!/bin/bash

# Variables
FFMPEG_VERSION=n5.1.3
NUM_CORES=$(nproc)

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
  case "$1" in
    "info") echo -e "${GREEN}[INFO] $2${NC}" ;;
    "warn") echo -e "${YELLOW}[WARN] $2${NC}" ;;
    "error") echo -e "${RED}[ERROR] $2${NC}" ;;
    *) echo "$2" ;;
  esac
}

# Update and install dependencies
print_message "info" "Updating system and installing dependencies..."
sudo apt-get update -y
sudo apt-get install -y \
    autoconf automake build-essential cmake git-core libass-dev libfreetype6-dev \
    libsdl2-dev libtool libvorbis-dev libvpx-dev pkg-config texinfo wget yasm zlib1g-dev \
    libx264-dev libx265-dev libnuma-dev libfdk-aac-dev libmp3lame-dev libopus-dev libfreetype6-dev \
    libfontconfig1-dev libfribidi-dev libgnutls28-dev libaom-dev

# Download and install nasm
print_message "info" "Installing nasm..."
cd /tmp
wget https://www.nasm.us/pub/nasm/releasebuilds/2.15.05/nasm-2.15.05.tar.bz2
tar xjf nasm-2.15.05.tar.bz2
cd nasm-2.15.05
./autogen.sh
./configure --prefix=/usr
make -j$NUM_CORES
sudo make install

# Clone FFmpeg source
print_message "info" "Cloning FFmpeg source..."
cd ~
git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg
cd ffmpeg
git checkout $FFMPEG_VERSION

# Configure FFmpeg with NVIDIA support (CUDA 12.2 paths)
print_message "info" "Configuring FFmpeg with NVIDIA support..."
./configure \
  --prefix=/usr/local \
  --enable-cuda-nvcc \
  --enable-libnpp \
  --extra-cflags=-I/usr/local/cuda-12.2/include \
  --extra-ldflags=-L/usr/local/cuda-12.2/lib64 \
  --enable-nonfree \
  --enable-libfdk-aac \
  --enable-libass \
  --enable-libfreetype \
  --enable-libmp3lame \
  --enable-libopus \
  --enable-libvorbis \
  --enable-libvpx \
  --enable-libx264 \
  --enable-libx265 \
  --enable-nvenc \
  --enable-gpl \
  --enable-libdrm \
  --enable-openssl \
  --enable-shared

# Compile and install FFmpeg
print_message "info" "Compiling FFmpeg..."
make -j$NUM_CORES
sudo make install

# Verify installation
print_message "info" "FFmpeg installed. Checking version..."
ffmpeg -version
