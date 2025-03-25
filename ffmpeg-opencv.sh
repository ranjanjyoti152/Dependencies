#!/bin/bash

# Install essential build tools
sudo apt install cmake -y
sudo apt install gcc g++ -y

# Install Python dependencies
sudo apt install python3 python3-dev python3-numpy -y

# Install FFmpeg and video-related dependencies
sudo apt install ffmpeg -y
sudo apt install libavcodec-dev libavformat-dev libswscale-dev -y
sudo apt install libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev -y

# Install GUI and image format dependencies
sudo apt install libgtk-3-dev -y
sudo apt install libpng-dev libjpeg-dev libopenexr-dev libtiff-dev libwebp-dev -y

# Clone OpenCV repositories
git clone https://github.com/opencv/opencv.git
git clone https://github.com/opencv/opencv_contrib.git

# Navigate and create build directory
cd ~/opencv
mkdir build
cd build

# Configure with CMake including FFmpeg support
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
-D HAVE_opencv_python3=ON \
-D WITH_FFMPEG=ON \
-D WITH_V4L=ON \
-D WITH_LIBV4L=ON \
..

# Compile and install
make -j8
sudo make install
sudo ldconfig

# Verify installation
echo "Verifying OpenCV installation..."
python3 -c "import cv2; print('OpenCV version:', cv2.__version__); print('CUDA enabled:', cv2.cuda.getCudaEnabledDeviceCount() > 0)"

echo "OpenCV installation with CUDA and FFmpeg support completed!"