#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Configuration
PYTHON_VERSION="3.12.8"
DOWNLOAD_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz"

echo "### Updating system and installing dependencies..."
sudo apt update

# FIXED: Removed spaces and simplified names for Ubuntu 24.04
sudo apt install -y build-essential libssl-dev zlib1g-dev libncurses-dev libreadline-dev libsqlite3-dev libgdbm-dev libdb5.3-dev libbz2-dev libexpat1-dev liblzma-dev libffi-dev wget curl

# Create a temporary directory for the build
BUILD_DIR="$HOME/python_build_tmp"
mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR"

echo "### Downloading Python ${PYTHON_VERSION}..."
wget -O python.tar.xz "$DOWNLOAD_URL"

echo "### Extracting source..."
tar -xf python.tar.xz
cd Python-${PYTHON_VERSION}

echo "### Configuring Python with optimizations..."
./configure --enable-optimizations --with-lto --enable-shared

echo "### Building (using $(nproc) cores)..."
make -j $(nproc)

echo "### Installing Python..."
sudo make altinstall
sudo ldconfig

echo "### Cleaning up..."
cd ~
rm -rf "$BUILD_DIR"

echo "------------------------------------------------"
echo "Installation Complete! Use: python3.12"
python3.12 --version
