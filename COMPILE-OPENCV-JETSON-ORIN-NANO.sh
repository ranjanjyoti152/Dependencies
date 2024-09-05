#!/bin/bash

# Update the system and install required dependencies
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y build-essential cmake git libgtk2.0-dev pkg-config \
                       libavcodec-dev libavformat-dev libswscale-dev python3-dev \
                       python3-numpy libtbb2 libtbb-dev libjpeg-dev libpng-dev \
                       libtiff-dev libdc1394-22-dev

# Set OpenCV version (you can change this to the version you need)
OPENCV_VERSION=4.5.5

# Download OpenCV and OpenCV Contrib sources
cd ~
git clone https://github.com/opencv/opencv.git
git clone https://github.com/opencv/opencv_contrib.git
cd opencv
git checkout $OPENCV_VERSION
cd ../opencv_contrib
git checkout $OPENCV_VERSION

# Create build directory
cd ~/opencv
mkdir build
cd build

# Configure the build with CMake and enable CUDA
cmake -D CMAKE_BUILD_TYPE=RELEASE \
      -D CMAKE_INSTALL_PREFIX=/usr/local \
      -D OPENCV_EXTRA_MODULES_PATH=~/opencv_contrib/modules \
      -D WITH_CUDA=ON \
      -D CUDA_ARCH_BIN=8.7 \
      -D CUDA_ARCH_PTX= \
      -D ENABLE_FAST_MATH=1 \
      -D CUDA_FAST_MATH=1 \
      -D WITH_CUBLAS=1 \
      -D WITH_LIBV4L=ON \
      -D BUILD_opencv_python3=ON \
      -D BUILD_opencv_python2=OFF \
      -D BUILD_TESTS=OFF \
      -D BUILD_PERF_TESTS=OFF \
      -D BUILD_EXAMPLES=OFF ..

# Compile OpenCV (you can adjust the -j flag depending on the number of CPU cores)
make -j$(nproc)

# Install OpenCV
sudo make install
sudo ldconfig

# Clean up
cd ~
rm -rf ~/opencv ~/opencv_contrib

echo "OpenCV $OPENCV_VERSION with CUDA support has been installed successfully on Jetson Orin Nano."
