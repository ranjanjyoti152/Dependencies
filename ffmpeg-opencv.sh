#!/bin/bash

# OpenCV build script with CUDA and FFmpeg support
# Usage: ./build_opencv.sh [version]

set -e  # Exit on error

# Default OpenCV version
OPENCV_VERSION=${1:-4.8.0}
BUILD_DIR=~/opencv_build
INSTALL_DIR=/usr/local
NUM_JOBS=$(nproc)

echo "Building OpenCV ${OPENCV_VERSION} with CUDA and FFmpeg support"

# Install dependencies
echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y build-essential cmake git pkg-config libgtk-3-dev \
    libavcodec-dev libavformat-dev libswscale-dev libv4l-dev \
    libxvidcore-dev libx264-dev libjpeg-dev libpng-dev libtiff-dev \
    gfortran openexr libatlas-base-dev python3-dev python3-numpy \
    libtbb2 libtbb-dev libdc1394-22-dev

# Create build directory
mkdir -p $BUILD_DIR
cd $BUILD_DIR

# Download OpenCV and OpenCV contrib
echo "Downloading OpenCV ${OPENCV_VERSION}..."
[ -d "opencv" ] || git clone https://github.com/opencv/opencv.git
[ -d "opencv_contrib" ] || git clone https://github.com/opencv/opencv_contrib.git

# Checkout the specified version
cd opencv
git fetch --all --tags
git checkout $OPENCV_VERSION
cd ../opencv_contrib
git fetch --all --tags
git checkout $OPENCV_VERSION
cd ..

# Create build directory
mkdir -p opencv/build
cd opencv/build

# Check if CUDA is installed
CUDA_FLAGS=""
if [ -d "/usr/local/cuda" ]; then
    echo "CUDA found, enabling CUDA support..."
    CUDA_FLAGS="-D WITH_CUDA=ON \
                -D CUDA_ARCH_BIN=7.5,8.0,8.6 \
                -D CUDA_ARCH_PTX= \
                -D OPENCV_DNN_CUDA=ON \
                -D ENABLE_FAST_MATH=ON \
                -D CUDA_FAST_MATH=ON \
                -D WITH_CUBLAS=ON"
else
    echo "CUDA not found, building without CUDA support."
    echo "Install CUDA first if you want CUDA support."
fi

# Configure OpenCV
echo "Configuring OpenCV build..."
cmake -D CMAKE_BUILD_TYPE=RELEASE \
      -D CMAKE_INSTALL_PREFIX=$INSTALL_DIR \
      -D OPENCV_EXTRA_MODULES_PATH=../../opencv_contrib/modules \
      -D INSTALL_PYTHON_EXAMPLES=ON \
      -D INSTALL_C_EXAMPLES=OFF \
      -D OPENCV_GENERATE_PKGCONFIG=ON \
      -D BUILD_EXAMPLES=ON \
      -D WITH_FFMPEG=ON \
      -D WITH_TBB=ON \
      -D WITH_GTK=ON \
      -D WITH_V4L=ON \
      -D WITH_OPENGL=ON \
      -D BUILD_TIFF=ON \
      $CUDA_FLAGS \
      ..

# Build OpenCV
echo "Building OpenCV with $NUM_JOBS jobs..."
make -j$NUM_JOBS

# Install OpenCV
echo "Installing OpenCV..."
sudo make install
sudo ldconfig

echo "OpenCV $OPENCV_VERSION with CUDA and FFmpeg support installed successfully!"
echo "Installation path: $INSTALL_DIR"
