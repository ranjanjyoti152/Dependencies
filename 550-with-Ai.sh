#!/bin/bash
echo "###############################################################################################################################################"
echo "##############################                                                                              ###################################"
echo "##############################                            WELCOME TO PROXPC                                 ###################################"
echo "##############################                                                                              ###################################"
echo "###############################################################################################################################################"
# Remove Unwanted Programs / clean up Broken packages .
sudo apt -y remove --purge "^libcuda.*"
sudo apt -y remove --purge "^cuda.*"
sudo apt -y remove --purge "^libnvidia.*"
sudo apt -y remove --purge "^nvidia.*"
sudo apt -y remove --purge "^tensorrt.*"
# Update And Upgrade everything 
sudo apt update 
sudo apt upgrade -y
sudo apt install gparted -y
sudo apt autoremove -y
sudo apt install git -y
sudo apt install net-tools -y
sudo apt install openssh-server -y
sudo apt install curl -y
sudo snap install ssd-benchmark
gsettings set org.gnome.desktop.background picture-uri https://raw.githubusercontent.com/ranjanjyoti152/opencvproxpc/main/Wallpaper-01.jpg
echo "########################################### Installing Nvidia Drivers #############################################################################"
sudo add-apt-repository ppa:graphics-drivers/ppa -y
sudo apt install nvidia-driver-550 -y
sudo dpkg --configure -a
echo "########################################### Installing Nvidia CUDA #############################################################################"
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-ubuntu2004.pin
sudo mv cuda-ubuntu2004.pin /etc/apt/preferences.d/cuda-repository-pin-600
wget https://developer.download.nvidia.com/compute/cuda/12.4.0/local_installers/cuda-repo-ubuntu2004-12-4-local_12.4.0-550.54.14-1_amd64.deb
sudo dpkg -i cuda-repo-ubuntu2004-12-4-local_12.4.0-550.54.14-1_amd64.deb
sudo cp /var/cuda-repo-ubuntu2004-12-4-local/cuda-*-keyring.gpg /usr/share/keyrings/
sudo apt-get update
sudo apt-get -y install cuda-toolkit-12-4
sudo apt install nvidia-cuda-toolkit -y
# Installing Library For AI 
wget https://developer.download.nvidia.com/compute/cudnn/9.0.0/local_installers/cudnn-local-repo-ubuntu2004-9.0.0_1.0-1_amd64.deb
sudo dpkg -i cudnn-local-repo-ubuntu2004-9.0.0_1.0-1_amd64.deb
sudo cp /var/cudnn-local-repo-ubuntu2004-9.0.0/cudnn-*-keyring.gpg /usr/share/keyrings/
sudo apt-get update
sudo apt-get -y install cudnn-cuda-12
# Compile OPENCV 
sudo apt-get install -y build-essential cmake git unzip pkg-config make
sudo apt-get install -y python3.8-dev python3-numpy libtbb2 libtbb-dev
sudo apt-get install -y  libjpeg-dev libpng-dev libtiff-dev libgtk2.0-dev libavcodec-dev libavformat-dev libswscale-dev libdc1394-22-dev libeigen3-dev libtheora-dev libvorbis-dev libxvidcore-dev libx264-dev sphinx-common libtbb-dev yasm libfaac-dev libopencore-amrnb-dev libopencore-amrwb-dev libopenexr-dev libgstreamer-plugins-base1.0-dev libavutil-dev libavfilter-dev libavresample-dev
mkdir ~/opencv_build && cd ~/opencv_build
git clone https://github.com/opencv/opencv
git clone https://github.com/opencv/opencv_contrib
cd ~/opencv_build/opencv
mkdir -p build && cd build
cmake -D WITH_CUDA=OFF -D BUILD_TIFF=ON -D BUILD_opencv_java=OFF -D WITH_OPENGL=ON -D WITH_OPENCL=ON -D WITH_IPP=ON -D WITH_TBB=ON -D WITH_EIGEN=ON -D WITH_V4L=ON -D WITH_VTK=OFF -D BUILD_TESTS=OFF -D BUILD_PERF_TESTS=OFF -D CMAKE_BUILD_TYPE=RELEASE -D BUILD_opencv_python2=OFF -D CMAKE_INSTALL_PREFIX=/usr/local -D PYTHON3_INCLUDE_DIR=$(python3 -c "from distutils.sysconfig import get_python_inc; print(get_python_inc())") -D PYTHON3_PACKAGES_PATH=$(python3 -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())") -D INSTALL_C_EXAMPLES=ON -D INSTALL_PYTHON_EXAMPLES=ON -D OPENCV_ENABLE_NONFREE=ON -D OPENCV_GENERATE_PKGCONFIG=ON -D PYTHON3_EXECUTABLE=$(which python3) -D PYTHON_DEFAULT_EXECUTABLE=$(which python3) -D OPENCV_EXTRA_MODULES_PATH=~/opencv_build/opencv_contrib/modules -D BUILD_EXAMPLES=ON ..
make -j8
sudo make install
echo "###############################################################################################################################################"
echo "##############################                                                                              ###################################"
echo "##############################                            INSTALLATION COMPLETE                             ###################################"
echo "##############################                       REBOOT YOUR MACHINE TO APPLY CHANGES                   ###################################"
echo "###############################################################################################################################################"
