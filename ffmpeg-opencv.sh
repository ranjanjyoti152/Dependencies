#!/bin/bash

# Exit on any error
set -e

# Initialize log file
LOG_FILE="compile_opencv.log"
echo "Starting OpenCV compilation process at $(date)" > "$LOG_FILE"

# Function for logging
log() {
    echo "$1"
    echo "$(date): $1" >> "$LOG_FILE"
}

# Function for error handling
handle_error() {
    log "Error: $1"
    exit 1
}

# Update package lists
log "Updating package lists..."
sudo apt-get update || handle_error "Failed to update package lists"

# Install dependencies
log "Installing build dependencies..."
sudo apt-get install -y \
    build-essential \
    cmake \
    git \
    pkg-config \
    libjpeg-dev \
    libtiff-dev \
    libpng-dev \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    libv4l-dev \
    libxvidcore-dev \
    libx264-dev \
    libgtk-3-dev \
    libatlas-base-dev \
    gfortran \
    python3-dev || handle_error "Failed to install dependencies"

# Note: libdc1394-22-dev is deprecated in newer Ubuntu versions and has been skipped

# Clone OpenCV if not already present
if [ ! -d "opencv" ]; then
    log "Cloning OpenCV repository..."
    git clone https://github.com/opencv/opencv.git || handle_error "Failed to clone OpenCV repository"
else
    log "OpenCV repository already exists. Updating..."
    cd opencv
    git pull
    cd ..
fi

# Clone OpenCV contrib if not already present
if [ ! -d "opencv_contrib" ]; then
    log "Cloning OpenCV contrib repository..."
    git clone https://github.com/opencv/opencv_contrib.git || handle_error "Failed to clone OpenCV contrib repository"
else
    log "OpenCV contrib repository already exists. Updating..."
    cd opencv_contrib
    git pull
    cd ..
fi

# Create build directory
log "Creating build directory..."
cd opencv
mkdir -p build
cd build

# Configure OpenCV build with CMake
log "Configuring OpenCV build with CMake..."
cmake -D CMAKE_BUILD_TYPE=RELEASE \
    -D CMAKE_INSTALL_PREFIX=/usr/local \
    -D OPENCV_EXTRA_MODULES_PATH=../../opencv_contrib/modules \
    -D WITH_FFMPEG=ON \
    -D WITH_V4L=ON \
    -D WITH_GSTREAMER=ON \
    -D BUILD_opencv_python3=ON \
    -D OPENCV_ENABLE_NONFREE=ON \
    -D INSTALL_PYTHON_EXAMPLES=OFF \
    -D INSTALL_C_EXAMPLES=OFF \
    -D BUILD_EXAMPLES=OFF .. || handle_error "CMake configuration failed"

# Get number of CPU cores for parallel compilation
NUM_CORES=$(nproc)
log "Detected $NUM_CORES CPU cores for parallel compilation"

# Compile OpenCV
log "Compiling OpenCV using $NUM_CORES cores..."
make -j"$NUM_CORES" || handle_error "Compilation failed"

# Install OpenCV
log "Installing OpenCV..."
sudo make install || handle_error "Installation failed"

# Update shared library cache
log "Updating shared library cache..."
sudo ldconfig || handle_error "Failed to update shared library cache"

# Verify installation
log "Verifying OpenCV installation..."
if opencv_version > /dev/null 2>&1; then
    VERSION=$(opencv_version)
    log "OpenCV $VERSION has been successfully installed!"
    log "Installation completed successfully. FFmpeg support is enabled."
    log "You can now use OpenCV with RTSP streams including H.264 and H.265 formats."
else
    handle_error "OpenCV installation verification failed"
fi

log "Build process completed. Check $LOG_FILE for detailed build information."
