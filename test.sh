#!/bin/bash

# Update the package list and upgrade existing packages
sudo apt-get update -y
sudo apt-get upgrade -y

# Check if build-essential and C++ development tools are already installed
if ! command -v g++ >/dev/null 2>&1; then
  sudo apt-get install -y build-essential g++ cmake
  echo "build-essential and C++ development tools installed."
else
  echo "build-essential and C++ development tools already installed."
fi

# Check if Python and pip are already installed
if ! command -v python3 >/dev/null 2>&1; then
  sudo apt-get install -y python3 python3-pip
  echo "Python and pip installed."
else
  echo "Python and pip already installed."
fi

# Check if numpy, scipy and matplotlib are already installed
if ! python3 -c 'import numpy' >/dev/null 2>&1; then
  pip3 install numpy scipy matplotlib
  echo "numpy, scipy and matplotlib installed."
else
  echo "numpy, scipy and matplotlib already installed."
fi

# Check if TensorFlow is already installed
if ! python3 -c 'import tensorflow' >/dev/null 2>&1; then
  pip3 install tensorflow
  echo "TensorFlow installed."
else
  echo "TensorFlow already installed."
fi

# Check if OpenCV is already installed
if ! pkg-config --modversion opencv4 >/dev/null 2>&1; then
  sudo apt-get install -y libopencv-dev python3-opencv
  echo "OpenCV installed."
else
  echo "OpenCV already installed."
fi

# Check if other dependencies are already installed
if ! dpkg -s libprotobuf-dev libgoogle-glog-dev libgflags-dev libhdf5-dev >/dev/null 2>&1; then
  sudo apt-get install -y libprotobuf-dev protobuf-compiler libgoogle-glog-dev libgflags-dev libhdf5-dev
  echo "Other dependencies installed."
else
  echo "Other dependencies already installed."
fi

#!/bin/bash

# Update the package list and upgrade existing packages
sudo apt-get update -y
sudo apt-get upgrade -y

# Install build-essential and C++ development tools
sudo apt-get install -y build-essential g++ cmake

# Install Python and pip
sudo apt-get install -y python3 python3-pip

# Install numpy, scipy and matplotlib for scientific computing
pip3 install numpy scipy matplotlib

# Install TensorFlow for machine learning
pip3 install tensorflow

# Install OpenCV for computer vision
sudo apt-get install -y libopencv-dev python3-opencv

# Install other dependencies for AI development
sudo apt-get install -y libprotobuf-dev protobuf-compiler libgoogle-glog-dev libgflags-dev libhdf5-dev

# Install NVIDIA drivers using ubuntu-drivers tool
sudo apt-get install -y ubuntu-drivers-common
sudo ubuntu-drivers autoinstall || {
    echo "NVIDIA driver installation using ubuntu-drivers failed, trying manual installation..."
    sudo apt-get remove -y --purge '^nvidia-.*'
    sudo apt-get autoremove -y
    sudo apt-get install -y nvidia-driver-460 || {
        echo "NVIDIA driver installation failed, trying to install an older version..."
        sudo apt-get install -y nvidia-driver-450 || {
            echo "NVIDIA driver installation failed, please install NVIDIA drivers manually."
            exit 1
        }
    }
}

# Install CUDA
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/cuda-ubuntu2004.pin
sudo mv cuda-ubuntu2004.pin /etc/apt/preferences.d/cuda-repository-pin-600
wget https://developer.download.nvidia.com/compute/cuda/11.6.0/local_installers/cuda-repo-ubuntu2004-11-6-local_11.6.0-510.39.01-1_amd64.deb
sudo dpkg -i cuda-repo-ubuntu2004-11-6-local_11.6.0-510.39.01-1_amd64.deb || {
    echo "CUDA installation failed, trying an alternate installation method..."
    wget https://developer.download.nvidia.com/compute/cuda/11.6.0/local_installers/cuda_11.6.0-510.39.01_linux.run
    sudo sh cuda_11.6.0-510.39.01_linux.run --silent --toolkit --override || {
        echo "CUDA installation failed, please install CUDA manually."
        exit 1
    }
}

# Install cuDNN
wget https://developer.download.nvidia.com/compute/cuda/11.6.0/local_installers/cuda_11.6.0_510.39.01_linux.run
sudo sh cuda_11.6.0_510.39.01_linux.run --silent --toolkit --override || {
    echo "cuDNN installation failed, trying an alternate installation method..."
    wget https://developer.nvidia.com/compute/machine-learning/cudnn/secure/8.2.2.26/11.6_20220127/cudnn-11.6-linux-x64-v8.2.2.26.tgz
    tar -xzvf cudnn-11.6-linux-x64-v8.2.2.26.tgz
    sudo cp -P cuda/include/cudnn*.h /usr/local/cuda/include
    sudo cp -P cuda/lib64/libcudnn*

