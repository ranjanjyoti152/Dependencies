#!/bin/bash

# Script to install PyTorch on JetPack 5.1.2 using a specific wheel file.

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

# Define the URL for the PyTorch wheel
TORCH_WHEEL_URL="https://developer.download.nvidia.com/compute/redist/jp/v512/pytorch/torch-2.1.0a0+41361538.nv23.06-cp38-cp38-linux_aarch64.whl"

# Download the PyTorch wheel with the correct filename
echo "Downloading PyTorch wheel from NVIDIA..."
if ! wget "$TORCH_WHEEL_URL"; then
  echo "Error: Failed to download the PyTorch wheel. Please check the URL or your internet connection." >&2
  exit 1
fi

# Get the downloaded filename from the URL
TORCH_WHEEL_FILE=$(basename "$TORCH_WHEEL_URL")

# Install the PyTorch wheel
echo "Installing PyTorch..."
if ! pip install "$TORCH_WHEEL_FILE"; then
  echo "Error: Failed to install PyTorch from the wheel file." >&2
  rm -f "$TORCH_WHEEL_FILE"
  exit 1
fi

# Cleanup downloaded wheel file
rm -f "$TORCH_WHEEL_FILE"

# Verify the installation of PyTorch
echo "Verifying PyTorch installation..."
if ! python3 -c "import torch; print('PyTorch version:', torch.__version__)"; then
  echo "Error: Verification failed. PyTorch might not be installed correctly." >&2
  exit 1
fi

# Install torchvision (compatible version)
echo "Installing torchvision..."
if ! pip install torchvision; then
  echo "Error: Failed to install torchvision. Please ensure compatibility with the installed PyTorch version." >&2
  exit 1
fi

# Verify the installation of torchvision
echo "Verifying torchvision installation..."
if ! python3 -c "import torchvision; print('torchvision version:', torchvision.__version__)"; then
  echo "Error: Verification failed. torchvision might not be installed correctly." >&2
  exit 1
fi

# Test PyTorch GPU availability
echo "Testing PyTorch GPU availability..."
if ! python3 -c "import torch; print('CUDA is available:', torch.cuda.is_available())"; then
  echo "Error: Failed to test CUDA availability. PyTorch may not be configured correctly for GPU usage." >&2
  exit 1
fi

# Test torchvision functionality
echo "Testing torchvision functionality..."
if ! python3 -c "from torchvision import transforms; print('torchvision.transforms is available:', transforms is not None)"; then
  echo "Error: Failed to test torchvision functionality." >&2
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

Installation complete!

The virtual environment will be activated automatically on login.

To manually activate the virtual environment:
1. Run: source $VENV_DIR/bin/activate
2. To deactivate, run: deactivate

PyTorch and torchvision installation verified successfully!

EOF
exit 0
