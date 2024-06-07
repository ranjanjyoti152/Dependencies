#!/bin/bash
sudo apt install cmake -y
sudo apt install gcc g++ -y

sudo apt install python3 python3-dev python3-numpy -y

sudo apt install libavcodec-dev libavformat-dev libswscale-dev -y
sudo apt install libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev -y
sudo apt install libgtk-3-dev -y
sudo apt install libpng-dev libjpeg-dev libopenexr-dev libtiff-dev libwebp-dev -y
git clone https://github.com/opencv/opencv.git
git clone https://github.com/opencv/opencv_contrib.git
 cd ~/opencv
 mkdir build
 cd build

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
..

make -j 8

sudo make install

