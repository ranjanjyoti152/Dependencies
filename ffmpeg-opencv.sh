#!/bin/bash

# Update package list
sudo apt update

# Install build tools and dependencies
sudo apt install -y cmake gcc g++ python3 python3-dev python3-pip
sudo pip3 install numpy
sudo apt install -y libavcodec-dev libavformat-dev libswscale-dev libv4l-dev
sudo apt install -y libxvidcore-dev libx264-dev ffmpeg
sudo apt install -y libgtk-3-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
sudo apt install -y libdc1394-22-dev libtbb-dev
sudo apt install -y libjpeg-dev libpng-dev libtiff-dev libopenexr-dev libwebp-dev

# Install CUDA toolkit (assuming NVIDIA drivers are already installed)
sudo apt install -y nvidia-cuda-toolkit

# Clone OpenCV repositories
cd ~
git clone https://github.com/opencv/opencv.git
git clone https://github.com/opencv/opencv_contrib.git

# Navigate and create build directory
cd ~/opencv
mkdir build
cd build

# Get Python 3 executable and library paths
PYTHON3_EXECUTABLE=$(which python3)
PYTHON3_INCLUDE_DIR=$(python3 -c "import sysconfig; print(sysconfig.get_path('include'))")
PYTHON3_LIBRARY=$(python3 -c "import sysconfig; print(sysconfig.get_config_var('LIBDIR') + '/libpython' + sysconfig.get_config_var('LDVERSION') + '.so')")

# Configure with CMake
cmake \
-D CMAKE_BUILD_TYPE=RELEASE \
-D CMAKE_INSTALL_PREFIX=/usr/local \
-D WITH_CUDA=ON \
-D WITH_CUDNN=ON \
-D WITH_CUBLAS=ON \
-D WITH_TBB=ON \
-D OPENCV_DNN_CUDA=ON \
-D OPENCV_ENABLE_NONFREE=ON \
-D CUDA_ARCH_BIN=8.6 \
-D OPENCV_EXTRA_MODULES_PATH=$HOME/opencv_contrib/modules \
-D BUILD_EXAMPLES=OFF \
-D WITH_FFMPEG=ON \
-D WITH_V4L=ON \
-D WITH_LIBV4L=ON \
-D PYTHON3_EXECUTABLE="$PYTHON3_EXECUTABLE" \
-D PYTHON3_INCLUDE_DIR="$PYTHON3_INCLUDE_DIR" \
-D PYTHON3_LIBRARY="$PYTHON3_LIBRARY" \
-D BUILD_opencv_python3=ON \
-D INSTALL_PYTHON_EXAMPLES=OFF \
..

# Compile and install
make -j8
sudo make install
sudo ldconfig

# Verify installation
echo "Verifying OpenCV installation..."
python3 -c "import cv2; print('OpenCV version:', cv2.__version__); print('CUDA enabled:', cv2.cuda.getCudaEnabledDeviceCount() > 0)"

# Clean up
cd ~
rm -rf opencv opencv_contrib

echo "OpenCV installation with CUDA and FFmpeg support completed!"