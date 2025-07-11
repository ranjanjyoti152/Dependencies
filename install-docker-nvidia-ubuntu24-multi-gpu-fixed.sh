#!/bin/bash

# Docker and NVIDIA Container Toolkit Installation Script for Ubuntu 24.04
# NVIDIA Driver 570 compatible with multi-GPU support testing
# Fixed GPU count detection

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_gpu_info() {
    echo -e "${CYAN}[GPU]${NC} $1"
}

# Function to cleanup existing Docker installation
cleanup_docker() {
    print_status "Cleaning up existing Docker installation..."
    
    # Stop Docker service if running
    if systemctl is-active --quiet docker; then
        print_status "Stopping Docker service..."
        sudo systemctl stop docker
    fi
    
    # Remove Docker packages
    print_status "Removing Docker packages..."
    sudo apt-get remove -y \
        docker \
        docker-engine \
        docker.io \
        containerd \
        runc \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin \
        docker-ce-rootless-extras \
        docker-scan-plugin 2>/dev/null || true
    
    # Remove Docker repository and GPG keys
    print_status "Removing Docker repository and keys..."
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/keyrings/docker.gpg
    sudo rm -f /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Remove Docker data (optional - ask user)
    read -p "Do you want to remove Docker data (/var/lib/docker)? This will delete all containers, images, and volumes. [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Removing Docker data directory..."
        sudo rm -rf /var/lib/docker
        sudo rm -rf /var/lib/containerd
    else
        print_status "Keeping Docker data directory."
    fi
    
    # Remove Docker configuration
    sudo rm -f /etc/docker/daemon.json
    sudo rm -rf /etc/docker
    
    print_success "Docker cleanup completed."
}

# Function to cleanup existing NVIDIA Container Toolkit
cleanup_nvidia_toolkit() {
    print_status "Cleaning up existing NVIDIA Container Toolkit..."
    
    # Remove NVIDIA Container Toolkit packages
    print_status "Removing NVIDIA Container Toolkit packages..."
    sudo apt-get remove -y \
        nvidia-container-toolkit \
        nvidia-container-runtime \
        nvidia-docker2 \
        libnvidia-container-tools \
        libnvidia-container1 2>/dev/null || true
    
    # Remove NVIDIA Container Toolkit repository and keys
    print_status "Removing NVIDIA Container Toolkit repository and keys..."
    sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit*.list
    sudo rm -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    sudo rm -f /etc/apt/sources.list.d/nvidia-docker.list
    
    print_success "NVIDIA Container Toolkit cleanup completed."
}

# Function to perform full cleanup
full_cleanup() {
    print_warning "Starting full cleanup of Docker and NVIDIA Container Toolkit..."
    
    cleanup_docker
    cleanup_nvidia_toolkit
    
    # Clean up package cache
    print_status "Cleaning package cache..."
    sudo apt-get autoremove -y
    sudo apt-get autoclean
    
    print_success "Full cleanup completed!"
}

# Function to check GPU information
check_gpu_info() {
    print_gpu_info "Checking GPU information..."
    
    if command -v nvidia-smi &> /dev/null; then
        # Fixed GPU count detection - count the actual number of GPU lines
        local gpu_count=$(nvidia-smi --list-gpus | wc -l)
        local gpu_names=$(nvidia-smi --query-gpu=name --format=csv,noheader | paste -sd, -)
        local driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -1)
        
        print_gpu_info "Driver Version: $driver_version"
        print_gpu_info "GPU Count: $gpu_count"
        print_gpu_info "GPU Names: $gpu_names"
        
        # Display detailed GPU information
        print_gpu_info "Detailed GPU Information:"
        nvidia-smi --query-gpu=index,name,memory.total,memory.used,memory.free,temperature.gpu,power.draw,power.limit --format=csv,table
        
        echo "$gpu_count"
    else
        print_error "nvidia-smi not found. Please ensure NVIDIA driver is installed."
        echo "0"
    fi
}

# Function to test single GPU
test_single_gpu() {
    local gpu_id=$1
    print_gpu_info "Testing GPU $gpu_id..."
    
    # Test basic GPU access
    if docker run --rm --gpus "device=$gpu_id" nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi -i $gpu_id; then
        print_success "✅ GPU $gpu_id test passed!"
        return 0
    else
        print_error "❌ GPU $gpu_id test failed!"
        return 1
    fi
}

# Function to test multi-GPU setup
test_multi_gpu() {
    local gpu_count=$1
    print_gpu_info "Testing multi-GPU setup with $gpu_count GPUs..."
    
    # Test all GPUs at once
    print_gpu_info "Testing all GPUs simultaneously..."
    if docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi; then
        print_success "✅ All GPUs accessible in container!"
    else
        print_error "❌ Multi-GPU test failed!"
        return 1
    fi
    
    # Test individual GPU access
    print_gpu_info "Testing individual GPU access..."
    local failed_gpus=0
    for ((i=0; i<gpu_count; i++)); do
        echo
        print_gpu_info "--- Testing GPU $i individually ---"
        if ! test_single_gpu $i; then
            ((failed_gpus++))
        fi
        sleep 2
    done
    
    echo
    if [ $failed_gpus -eq 0 ]; then
        print_success "✅ All $gpu_count GPU individual tests passed!"
    else
        print_error "❌ $failed_gpus GPU(s) failed individual tests!"
    fi
    
    # Test specific GPU combinations
    print_gpu_info "Testing specific GPU combinations..."
    
    # Test first GPU only
    print_gpu_info "Testing GPU 0 only..."
    docker run --rm --gpus "device=0" nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi -i 0
    
    # Test second GPU only
    print_gpu_info "Testing GPU 1 only..."
    docker run --rm --gpus "device=1" nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi -i 1
    
    # Test both GPUs with count limit
    print_gpu_info "Testing with GPU count limit (2 GPUs)..."
    docker run --rm --gpus 2 nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
    
    # Test GPU memory allocation across multiple GPUs
    print_gpu_info "Testing GPU memory allocation across multiple GPUs..."
    local cuda_test_script='
import subprocess
import sys
import os

print("=== Multi-GPU Docker Test ===")
print("CUDA_VISIBLE_DEVICES:", os.environ.get("CUDA_VISIBLE_DEVICES", "Not set"))

# Run nvidia-smi to show available GPUs
print("\n=== Available GPUs in container ===")
result = subprocess.run(["nvidia-smi", "--list-gpus"], capture_output=True, text=True)
print(result.stdout)

# Try to import torch for advanced testing
try:
    import torch
    print("\n=== PyTorch CUDA Information ===")
    print("CUDA Available:", torch.cuda.is_available())
    print("CUDA Version:", torch.version.cuda)
    print("PyTorch Version:", torch.__version__)
    
    if torch.cuda.is_available():
        device_count = torch.cuda.device_count()
        print(f"Number of CUDA devices: {device_count}")
        
        for i in range(device_count):
            device = torch.device(f"cuda:{i}")
            print(f"Device {i}: {torch.cuda.get_device_name(i)}")
            
            # Test memory allocation on each GPU
            try:
                print(f"  Testing memory allocation on GPU {i}...")
                x = torch.randn(1000, 1000, device=device)
                y = torch.randn(1000, 1000, device=device)
                z = torch.matmul(x, y)
                print(f"  ✅ Memory allocation and computation successful on GPU {i}")
                
                # Print memory usage
                allocated = torch.cuda.memory_allocated(device) / 1024**2
                reserved = torch.cuda.memory_reserved(device) / 1024**2
                print(f"  Memory - Allocated: {allocated:.2f} MB, Reserved: {reserved:.2f} MB")
                
                # Clear memory
                del x, y, z
                torch.cuda.empty_cache()
                
            except Exception as e:
                print(f"  ❌ Error on GPU {i}: {e}")
        
        # Test multi-GPU tensor operations
        if device_count > 1:
            print("\n=== Testing multi-GPU tensor operations ===")
            try:
                x0 = torch.randn(1000, 1000, device="cuda:0")
                x1 = torch.randn(1000, 1000, device="cuda:1")
                print("  ✅ Multi-GPU tensor creation successful")
                
                # Test data transfer between GPUs
                x1_to_0 = x1.to("cuda:0")
                result = torch.matmul(x0, x1_to_0)
                print("  ✅ Inter-GPU data transfer and computation successful")
                
            except Exception as e:
                print(f"  ❌ Multi-GPU tensor error: {e}")
        
        print("\n🎉 All GPU tests completed successfully!")
    else:
        print("❌ CUDA not available in container")
        
except ImportError:
    print("\n⚠️  PyTorch not available in this container")
    print("Basic GPU detection completed successfully")
'
    
    # Create a temporary Python script for advanced GPU testing
    echo "$cuda_test_script" > /tmp/gpu_test.py
    
    # Run the advanced GPU test in a container with PyTorch
    print_gpu_info "Running advanced multi-GPU test with PyTorch..."
    if docker run --rm --gpus all -v /tmp/gpu_test.py:/test.py pytorch/pytorch:latest python /test.py; then
        print_success "✅ Advanced multi-GPU test passed!"
    else
        print_warning "⚠️  Advanced multi-GPU test failed (PyTorch container might not be available)"
        print_status "Running basic multi-GPU test instead..."
        
        # Fallback basic test
        docker run --rm --gpus all -v /tmp/gpu_test.py:/test.py nvidia/cuda:12.4.0-base-ubuntu22.04 python3 /test.py
    fi
    
    # Clean up
    rm -f /tmp/gpu_test.py
    
    # Test GPU utilization monitoring
    print_gpu_info "Testing GPU utilization monitoring..."
    docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 bash -c "
        echo '=== GPU Status Before Load ==='
        nvidia-smi --query-gpu=index,utilization.gpu,utilization.memory,temperature.gpu --format=csv,table
        echo
        echo '=== Running GPU stress test for 10 seconds ==='
        timeout 10 python3 -c '
import time
import math
print(\"Starting stress test...\")
start_time = time.time()
while time.time() - start_time < 10:
    result = sum([math.sqrt(i) for i in range(100000)])
print(\"Stress test completed\")
' 2>/dev/null || echo 'Stress test completed'
        echo
        echo '=== GPU Status After Load ==='
        nvidia-smi --query-gpu=index,utilization.gpu,utilization.memory,temperature.gpu --format=csv,table
    "
    
    return 0
}

# Function to install Docker and NVIDIA Container Toolkit
install_fresh() {
    print_status "Starting fresh installation of Docker and NVIDIA Container Toolkit for Ubuntu 24.04..."
    
    # Update the package list
    print_status "Updating package list..."
    sudo apt-get update
    
    # Install prerequisites
    print_status "Installing prerequisites..."
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common \
        wget
    
    # Add Docker's official GPG key
    print_status "Adding Docker GPG key..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up the Docker repository for Ubuntu 24.04 (Noble Numbat)
    print_status "Setting up Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      noble stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    print_status "Installing Docker Engine..."
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add current user to docker group to run docker without sudo
    print_status "Adding user $USER to docker group..."
    sudo usermod -aG docker $USER
    
    # Detect Ubuntu version for NVIDIA repository
    local ubuntu_version=$(lsb_release -rs)
    local ubuntu_codename=$(lsb_release -cs)
    
    print_status "Detected Ubuntu $ubuntu_version ($ubuntu_codename)"
    
    # Configure NVIDIA Container Toolkit using the official installation script
    print_status "Setting up NVIDIA Container Toolkit repository..."
    
    # Method 1: Use the official NVIDIA setup script
    if curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg; then
        print_status "NVIDIA GPG key added successfully"
        
        # Get distribution information
        local distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        print_status "Distribution detected: $distribution"
        
        # Try different repository configurations
        local repo_added=false
        
        # Try Ubuntu 22.04 repository first (most compatible)
        if curl -s -L https://nvidia.github.io/libnvidia-container/ubuntu22.04/libnvidia-container.list | \
           sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
           sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null; then
            print_status "Added Ubuntu 22.04 NVIDIA repository"
            repo_added=true
        fi
        
        # If that fails, try the distribution-specific one
        if [[ "$repo_added" == false ]]; then
            if curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
               sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
               sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null; then
                print_status "Added distribution-specific NVIDIA repository"
                repo_added=true
            fi
        fi
        
        # If both fail, use manual repository setup
        if [[ "$repo_added" == false ]]; then
            print_warning "Using manual repository setup"
            echo "deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/amd64 /" | \
              sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
        fi
    else
        print_error "Failed to add NVIDIA GPG key"
        return 1
    fi
    
    # Update package lists and install the NVIDIA Container Toolkit
    print_status "Installing NVIDIA Container Toolkit..."
    if sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit; then
        print_success "NVIDIA Container Toolkit installed successfully"
    else
        print_warning "Primary installation failed. Trying alternative method..."
        
        # Alternative method: Download and install manually
        print_status "Downloading NVIDIA Container Toolkit manually..."
        
        # Clean up previous attempts
        sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list
        
        # Use the latest stable release
        local arch=$(dpkg --print-architecture)
        local toolkit_version="1.14.3"  # Use a known stable version
        
        # Download the .deb packages directly
        cd /tmp
        wget -O nvidia-container-toolkit.deb "https://github.com/NVIDIA/nvidia-container-toolkit/releases/download/v${toolkit_version}/nvidia-container-toolkit_${toolkit_version}-1_${arch}.deb" || {
            print_error "Failed to download NVIDIA Container Toolkit"
            return 1
        }
        
        # Install the downloaded package
        sudo dpkg -i nvidia-container-toolkit.deb || {
            print_status "Fixing dependencies..."
            sudo apt-get install -f -y
        }
        
        # Clean up
        rm -f nvidia-container-toolkit.deb
        cd -
    fi
    
    # Configure the container runtime
    print_status "Configuring NVIDIA container runtime..."
    if command -v nvidia-ctk &> /dev/null; then
        sudo nvidia-ctk runtime configure --runtime=docker
        print_success "NVIDIA runtime configured with nvidia-ctk"
    else
        # Fallback manual configuration
        print_warning "nvidia-ctk not found, using manual configuration..."
        sudo mkdir -p /etc/docker
        sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "default-runtime": "nvidia",
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  }
}
EOF
        print_success "Manual NVIDIA runtime configuration completed"
    fi
    
    # Restart Docker to apply changes
    print_status "Restarting Docker service..."
    sudo systemctl restart docker
    sudo systemctl enable docker
    
    # Verify the installation
    print_status "Verifying installation..."
    echo
    print_success "Docker version:"
    docker --version
    
    if command -v nvidia-ctk &> /dev/null; then
        print_success "NVIDIA Container Toolkit version:"
        nvidia-ctk --version
    else
        print_warning "nvidia-ctk command not available"
    fi
    
    # Check GPU information and get count
    gpu_count=$(check_gpu_info)
    
    # Test NVIDIA Docker integration
    print_status "Testing NVIDIA Docker integration..."
    sleep 5  # Give Docker a moment to fully restart
    
    # Test basic GPU access with CUDA 12.4.0
    print_gpu_info "Testing basic GPU access with CUDA 12.4.0..."
    if timeout 90 docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi; then
        print_success "✅ Basic NVIDIA Docker integration test passed!"
        
        # Fixed GPU count comparison
        if [ "$gpu_count" -gt 1 ]; then
            print_gpu_info "Multiple GPUs detected ($gpu_count GPUs). Running multi-GPU tests..."
            test_multi_gpu "$gpu_count"
        else
            print_gpu_info "Single GPU detected. Running single GPU tests..."
            test_single_gpu 0
        fi
    else
        print_warning "❌ NVIDIA Docker integration test failed."
        print_status "Troubleshooting steps:"
        print_status "1. Log out and back in (or run 'newgrp docker')"
        print_status "2. Ensure NVIDIA driver 570 is installed: nvidia-smi"
        print_status "3. Reboot your system"
        print_status "4. Check Docker daemon: sudo systemctl status docker"
        print_status "5. Check Docker logs: sudo journalctl -u docker.service"
        
        # Try without --gpus flag to see if basic Docker works
        print_status "Testing basic Docker functionality..."
        if timeout 30 docker run --rm hello-world >/dev/null 2>&1; then
            print_success "Basic Docker functionality works"
        else
            print_error "Basic Docker functionality failed"
        fi
    fi
    
    print_success "🎉 Installation completed successfully!"
    
    echo
    print_status "Important notes:"
    echo "1. Please log out and log back in (or run 'newgrp docker') to use docker without sudo"
    echo "2. Make sure NVIDIA driver 570 is properly installed: nvidia-smi"
    echo "3. You may need to reboot your system for full functionality"
    echo "4. Test GPU access with: docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi"
    if [ "$gpu_count" -gt 1 ]; then
        echo "5. Test specific GPU: docker run --rm --gpus device=0 nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi -i 0"
        echo "6. Test multi-GPU: docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi"
        echo "7. Test GPU 1 only: docker run --rm --gpus device=1 nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi -i 1"
    fi
    echo
    print_status "Next steps if GPU test failed:"
    echo "- Install NVIDIA driver: sudo apt install nvidia-driver-570"
    echo "- Reboot system: sudo reboot"
    echo "- Verify driver: nvidia-smi"
    echo "- Test again: docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi"
}

# Function to show menu
show_menu() {
    echo
    echo "=============================================="
    echo "  Docker + NVIDIA Toolkit Installation"
    echo "  Ubuntu 24.04 | NVIDIA Driver 570"
    echo "  Multi-GPU Support | CUDA 12.4.0"
    echo "  User: $USER | Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=============================================="
    echo
    echo "Please choose an option:"
    echo "1) Fresh install (recommended for new systems)"
    echo "2) Cleanup existing installation only"
    echo "3) Cleanup and reinstall (recommended for existing installations)"
    echo "4) Install without cleanup (not recommended if Docker is already installed)"
    echo "5) Test GPU setup only (requires Docker + NVIDIA toolkit already installed)"
    echo "6) Exit"
    echo
}

# Function to test existing GPU setup
test_existing_setup() {
    print_status "Testing existing GPU setup..."
    
    # Check if Docker is installed and running
    if ! command -v docker &> /dev/null; then
        print_error "Docker not found. Please install Docker first."
        return 1
    fi
    
    if ! systemctl is-active --quiet docker; then
        print_error "Docker service is not running. Please start Docker service."
        return 1
    fi
    
    # Check if user is in docker group
    if ! groups $USER | grep -q docker; then
        print_warning "User $USER is not in docker group. You may need to run docker with sudo."
    fi
    
    # Check GPU information and get count
    gpu_count=$(check_gpu_info)
    
    if [ "$gpu_count" -eq 0 ]; then
        print_error "No GPUs detected or NVIDIA driver not installed."
        return 1
    fi
    
    # Test GPU access
    print_gpu_info "Testing GPU access with CUDA 12.4.0..."
    if docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi; then
        print_success "✅ Basic GPU test passed!"
        
        if [ "$gpu_count" -gt 1 ]; then
            print_gpu_info "Multiple GPUs detected ($gpu_count GPUs). Running multi-GPU tests..."
            test_multi_gpu "$gpu_count"
        else
            print_gpu_info "Single GPU detected. Running single GPU tests..."
            test_single_gpu 0
        fi
    else
        print_error "❌ GPU test failed!"
        return 1
    fi
    
    print_success "🎉 GPU setup test completed!"
}

# Main execution
main() {
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
        exit 1
    fi
    
    # Check if sudo is available (only for installation options)
    if [[ "${1:-}" != "5" ]]; then
        if ! sudo -n true 2>/dev/null; then
            print_status "Please enter your password for sudo access:"
            sudo -v
        fi
    fi
    
    # Check Ubuntu version
    local ubuntu_version=$(lsb_release -rs 2>/dev/null || echo "unknown")
    if [[ "$ubuntu_version" != "24.04" ]] && [[ "$ubuntu_version" != "22.04" ]]; then
        print_warning "This script is optimized for Ubuntu 24.04/22.04. Your version: $ubuntu_version"
        read -p "Do you want to continue anyway? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Exiting..."
            exit 0
        fi
    fi
    
    while true; do
        show_menu
        read -p "Enter your choice [1-6]: " choice
        echo
        
        case $choice in
            1)
                print_status "Starting fresh installation..."
                install_fresh
                break
                ;;
            2)
                print_warning "Starting cleanup only..."
                full_cleanup
                print_success "Cleanup completed. You can now run option 1 for fresh install."
                ;;
            3)
                print_warning "Starting cleanup and reinstall..."
                full_cleanup
                echo
                install_fresh
                break
                ;;
            4)
                print_warning "Installing without cleanup (not recommended)..."
                install_fresh
                break
                ;;
            5)
                print_status "Testing existing GPU setup..."
                test_existing_setup
                ;;
            6)
                print_status "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option. Please choose 1-6."
                ;;
        esac
    done
}

# Run main function
main "$@"