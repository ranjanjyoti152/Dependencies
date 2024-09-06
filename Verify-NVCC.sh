#!/bin/bash

# Check if CUDA is installed and nvcc exists
if [ -f /usr/local/cuda/bin/nvcc ]; then
    echo "CUDA is installed, and nvcc found."

    # Check if the PATH is already in .bashrc
    if ! grep -q '/usr/local/cuda/bin' ~/.bashrc; then
        echo "Adding CUDA to PATH in .bashrc"
        echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
    else
        echo "CUDA path is already in .bashrc"
    fi

    # Source the .bashrc to apply changes
    source ~/.bashrc

    # Display the updated PATH
    echo "Current PATH: $PATH"

    # Verify nvcc version
    nvcc --version
else
    echo "CUDA or nvcc not found at /usr/local/cuda/bin/nvcc."
fi
