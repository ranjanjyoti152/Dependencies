#!/bin/bash

# Script to install PyTorch and torchvision on JetPack 5.1.2
# Includes manual fallback if NVIDIA-specific versions are unavailable.

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root." >&2
  exit 1
fi

# Update system packages
echo "Updating system packages..."
if ! apt update && apt upgrade -y; then
  echo "Error: Failed to update packages. Please check your internet connection." >&2
  exit 1
fi

# Install required dependencies
echo "Installing dependencies..."
if ! apt install -y python3-pip python3-dev python3-venv libopenblas-dev libopenmpi-dev libomp-dev wget; then
  echo "Error: Failed to install required dependencies." >&2
  exit 1
fi

# Create a Python virtual environment
VENV_DIR="/opt/torch_env"
echo "Creating Python virtual environment in '$VENV_DIR'..."
if ! python3 -m venv "$VENV_DIR"; then
  echo "Error: Failed to create a virtual environment." >&2
  exit 1
fi

# Activate the virtual environment
source "$VENV_DIR/bin/activate"

# Upgrade pip
echo "Upgrading pip to the latest version..."
if ! pip install --upgrade pip; then
  echo "Error: Failed to upgrade pip." >&2
  exit 1
fi

# Attempt to install PyTorch and torchvision from NVIDIA repository
TORCH_VERSION="2.1.0a0+41361538.nv23.06"
TORCHVISION_VERSION="0.14.0+nv22.09"
NVIDIA_REPO_URL="https://developer.download.nvidia.com/compute/redist/jp/v512"
echo "Attempting to install PyTorch ($TORCH_VERSION) and torchvision ($TORCHVISION_VERSION) from NVIDIA repository..."
if ! pip install "torch==$TORCH_VERSION" "torchvision==$TORCHVISION_VERSION" --extra-index-url "$NVIDIA_REPO_URL"; then
  echo "Warning: Failed to install from NVIDIA repository. Falling back to manual installation..."

  # Download PyTorch and torchvision wheel files manually
  echo "Downloading PyTorch and torchvision wheels..."
  wget -q --show-progress "$NVIDIA_REPO_URL/pytorch/torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl" -O torch.whl
  wget -q --show-progress "https://developer.download.nvidia.com/compute/redist/jp/v51/torchvision-0.14.0+nv22.09-cp38-cp38-linux_aarch64.whl" -O torchvision.whl

  echo "Installing downloaded wheels..."
  if ! pip install torch.whl torchvision.whl; then
    echo "Error: Failed to install PyTorch or torchvision from downloaded wheel files." >&2
    exit 1
  fi

  # Cleanup downloaded files
  rm -f torch.whl torchvision.whl
fi

# Verify the installation
echo "Verifying PyTorch and torchvision installation..."
if ! python3 -c "import torch; print('PyTorch version:', torch.__version__)" || \
   ! python3 -c "import torchvision; print('torchvision version:', torchvision.__version__)"; then
  echo "Error: Verification failed. PyTorch or torchvision might not be installed correctly." >&2
  exit 1
fi

# Automate virtual environment activation on startup
echo "Automating virtual environment activation on startup..."
PROFILE_FILE="/etc/profile.d/torch_env.sh"
cat <<EOF > "$PROFILE_FILE"
#!/bin/bash
# Automatically activate the virtual environment on terminal login
source $VENV_DIR/bin/activate
EOF
chmod +x "$PROFILE_FILE"
echo "Virtual environment activation script added to '$PROFILE_FILE'."

# Completion message
cat <<EOF

Installation and automation complete!

The virtual environment will be activated automatically on login.

To manually activate the virtual environment:
1. Run: source $VENV_DIR/bin/activate
2. To deactivate, run: deactivate

EOF
exit 0
