#!/bin/bash

# Variables
OPENCV_VERSION="4.10.0"
INSTALL_PREFIX="/usr/local"
CUDA_ARCH_BIN="8.6"

# Step 1: Update and Install Dependencies
sudo apt-get update
sudo apt-get install -y build-essential cmake git pkg-config libgtk-3-dev \
    libavcodec-dev libavformat-dev libswscale-dev libv4l-dev \
    libxvidcore-dev libx264-dev libjpeg-dev libpng-dev libtiff-dev \
    gfortran openexr libatlas-base-dev python3-dev python3-numpy \
    libtbb2 libtbb-dev libdc1394-22-dev libopenexr-dev \
    libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev \
    libavresample-dev

# Step 2: Clone OpenCV and OpenCV Contrib Repositories
if [ ! -d "opencv" ]; then
    git clone --branch $OPENCV_VERSION https://github.com/opencv/opencv.git
fi
if [ ! -d "opencv_contrib" ]; then
    git clone --branch $OPENCV_VERSION https://github.com/opencv/opencv_contrib.git
fi

# Step 3: Create Build Directory
cd opencv
mkdir -p build
cd build

# Step 4: Run CMake with CUDA Support
cmake -D CMAKE_BUILD_TYPE=Release \
      -D CMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
      -D OPENCV_EXTRA_MODULES_PATH=../../opencv_contrib/modules \
      -D WITH_CUDA=ON \
      -D CUDA_ARCH_BIN=$CUDA_ARCH_BIN \
      -D ENABLE_FAST_MATH=1 \
      -D CUDA_FAST_MATH=1 \
      -D WITH_CUBLAS=1 \
      -D BUILD_opencv_python3=ON \
      -D BUILD_EXAMPLES=OFF \
      -D PYTHON_EXECUTABLE=$(which python3) ..

# Step 5: Compile and Install
make -j$(nproc)
sudo make install
sudo ldconfig

# Step 6: Verify Installation
echo "OpenCV with CUDA has been installed successfully!"
python3 -c "import cv2; print(cv2.getBuildInformation())"
