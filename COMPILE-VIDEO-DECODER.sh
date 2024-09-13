#!/bin/bash

# Exit on any error
set -e

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

echo "Starting FFmpeg installation on Jetson..."

# Update and install dependencies
echo "Updating system and installing dependencies..."
sudo apt-get update
sudo apt-get install -y build-essential yasm pkg-config \
                        libavcodec-dev libavformat-dev libavfilter-dev \
                        libavdevice-dev libswscale-dev libswresample-dev \
                        libv4l-dev cmake git nvidia-l4t-core

# Install NVIDIA Jetson Multimedia API (needed for NVENC and hardware acceleration)
echo "Installing NVIDIA Jetson Multimedia API..."
sudo apt-get install -y nvidia-l4t-multimedia

# Install NV-Codec-Headers (needed for CUDA/NVENC support)
echo "Cloning and installing NV-Codec-Headers..."

# Remove the existing directory if it exists
if [ -d "$HOME/nv-codec-headers" ]; then
    echo "Removing previous NV-Codec-Headers directory..."
    rm -rf "$HOME/nv-codec-headers"
fi

# Clone the latest NV-Codec-Headers
cd $HOME
git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git
cd nv-codec-headers
sudo make install

# Clone the latest FFmpeg source from GitHub
echo "Cloning the latest FFmpeg source from GitHub..."
cd $HOME
if [ -d "ffmpeg" ]; then
    echo "Removing previous FFmpeg source directory..."
    rm -rf ffmpeg
fi
git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg
cd ffmpeg

# Clean any previous builds
echo "Cleaning up previous builds..."
make clean || true

# Configure FFmpeg with Jetson-specific NVIDIA support
echo "Configuring FFmpeg with NVIDIA support for Jetson..."

./configure --prefix=/usr/local \
            --enable-gpl \
            --enable-nonfree \
            --enable-cuda-nvcc \
            --enable-cuvid \
            --enable-nvenc \
            --extra-cflags="-I/usr/local/cuda/include -I/usr/local/include/ffnvcodec" \
            --extra-ldflags="-L/usr/local/cuda/lib64 -L/usr/lib/aarch64-linux-gnu" \
            --nvcc="/usr/local/cuda/bin/nvcc" \
            --disable-static \
            --enable-shared

# Compile FFmpeg
echo "Compiling FFmpeg..."
make -j"$(nproc)"

# Install FFmpeg
echo "Installing FFmpeg..."
sudo make install

# Update library path
echo "Updating library path..."
sudo ldconfig

# Verify FFmpeg installation
echo "Verifying FFmpeg installation..."
ffmpeg -version

# Clean up source files
echo "Cleaning up..."
cd "$HOME"
rm -rf ffmpeg

echo "FFmpeg installation complete!"
