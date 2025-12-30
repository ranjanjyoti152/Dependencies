#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Configuration
PYTHON_VERSION="3.12.8"
DOWNLOAD_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz"

echo "### Updating system and installing dependencies..."
sudo apt update
sudo apt install -y build-essential libssl-dev zlib1g-dev \
libncurses5-dev libncursesw5-dev lib readline-dev libsqlite3-dev \
libgdbm-dev libdb5.3-dev libbz2-dev libexpat1-dev liblzma-dev \
libffi-dev wget curl

# Create a temporary directory for the build
mkdir -p ~/python_build && cd ~/python_build

echo "### Downloading Python ${PYTHON_VERSION}..."
wget -O python.tar.xz "$DOWNLOAD_URL"

echo "### Extracting source..."
tar -xf python.tar.xz
cd Python-${PYTHON_VERSION}

echo "### Configuring Python with optimizations..."
# --enable-optimizations runs Profile Guided Optimization (PGO)
# --with-lto enables Link Time Optimization for better performance
./configure --enable-optimizations --with-lto --enable-shared

echo "### Building (this may take a while)..."
# Use all available CPU cores
make -j $(nproc)

echo "### Installing Python..."
# 'altinstall' prevents overwriting the default system python3 binary
sudo make altinstall

echo "### Cleaning up..."
sudo ldconfig  # Refresh shared library cache
cd ~
rm -rf ~/python_build

echo "------------------------------------------------"
echo "Installation Complete!"
echo "You can run Python 3.12 using: python3.12"
python3.12 --version
