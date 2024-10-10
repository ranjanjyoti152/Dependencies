#!/bin/bash
set -x  # Enable command tracing

# Variables
FFMPEG_VERSION=n5.1.3
NUM_CORES=$(nproc)
CUDA_VERSION=12.2

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
    libfontconfig1-dev libfribidi-dev libgnutls28-dev libaom-dev nvidia-cuda-toolkit

# Verify CUDA installation
print_message "info" "Verifying CUDA installation..."
nvcc --version
if [ $? -ne 0 ]; then
    print_message "error" "CUDA installation failed or nvcc is not in the PATH."
    exit 1
fi

# Set CUDA environment variables
print_message "info" "Setting CUDA environment variables..."
export PATH=/usr/local/cuda-$CUDA_VERSION/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-$CUDA_VERSION/lib64:$LD_LIBRARY_PATH

# Verify GCC version
print_message "info" "Checking GCC version..."
gcc --version
if [ $? -ne 0 ]; then
    print_message "error" "GCC is not installed."
    exit 1
fi

# Install GCC 10 if necessary
GCC_VERSION=$(gcc -dumpversion)
if [ "$GCC_VERSION" \< "10" ]; then
    print_message "info" "Installing GCC 10..."
    sudo apt-get install -y gcc-10 g++-10
    export CC=/usr/bin/gcc-10
    export CXX=/usr/bin/g++-10
fi

# Download and install NASM
print_message "info" "Installing NASM..."
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

# Configure FFmpeg with NVIDIA support
print_message "info" "Configuring FFmpeg with NVIDIA support..."
./configure \
  --prefix=/usr/local \
  --enable-cuda-nvcc \
  --nvcc=/usr/local/cuda-$CUDA_VERSION/bin/nvcc \
  --enable-libnpp \
  --extra-cflags=-I/usr/local/cuda-$CUDA_VERSION/include \
  --extra-ldflags=-L/usr/local/cuda-$CUDA_VERSION/lib64 \
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
