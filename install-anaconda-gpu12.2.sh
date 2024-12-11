#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Step 1: Install Anaconda
echo "Downloading Anaconda installer..."
ANACONDA_INSTALLER="Anaconda3-2023.03-Linux-x86_64.sh"
wget https://repo.anaconda.com/archive/$ANACONDA_INSTALLER

echo "Installing Anaconda..."
bash $ANACONDA_INSTALLER -b

# Add Anaconda to PATH
echo "Adding Anaconda to PATH..."
echo 'export PATH="$HOME/anaconda3/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Step 2: Install GPU libraries in Anaconda
echo "Setting up GPU support in Anaconda environment..."

# Create a new Conda environment
conda create -n gpu_env python=3.9 -y
conda activate gpu_env

# Install PyTorch with CUDA 12.2
echo "Installing PyTorch with CUDA 12.2 support..."
conda install pytorch torchvision torchaudio pytorch-cuda=12.2 -c pytorch -c nvidia -y

# Verify PyTorch GPU support
echo "Verifying PyTorch installation..."
python -c "import torch; print('CUDA Available:', torch.cuda.is_available()); print('CUDA Version:', torch.version.cuda)"

echo "Installation complete. Activate the Conda environment with 'conda activate gpu_env' to use GPU support."
