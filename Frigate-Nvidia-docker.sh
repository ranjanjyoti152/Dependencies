#!/bin/bash

# Set username and password for Frigate
USERNAME="Proxpc"
PASSWORD="12345"

# Set Frigate configuration path
FRIGATE_CONFIG_PATH="/opt/frigate"

# Update the package list
sudo apt-get update

# Install prerequisites
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Install Docker and NVIDIA Container Toolkit

# Add Docker’s official GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add NVIDIA GPG key and repository for the NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID) \
    && curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
    && curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Update package lists and install the NVIDIA Container Toolkit
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# Configure the Docker daemon to use the NVIDIA runtime by default
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

# Restart Docker to apply changes
sudo systemctl restart docker

# Verify the installation
docker --version
nvidia-container-cli --version

echo "Docker with NVIDIA support has been successfully installed."

# Create Frigate configuration directory
sudo mkdir -p $FRIGATE_CONFIG_PATH

# Create Frigate configuration file with CUDA and hardware decoding support
cat <<EOF | sudo tee $FRIGATE_CONFIG_PATH/config.yml > /dev/null
mqtt:
  host: mqtt
  user: $USERNAME
  password: $PASSWORD

detectors:
  coral:
    type: edgetpu
    device: usb

ffmpeg:
  hwaccel_args:
    - -hwaccel
    - nvdec
    - -c:v
    - h264_cuvid

cameras:
EOF

# Add all provided RTSP streams to the configuration
for i in {10..54}; do
  cat <<EOF | sudo tee -a $FRIGATE_CONFIG_PATH/config.yml > /dev/null
  camera_$i:
    ffmpeg:
      inputs:
        - path: rtsp://admin:admin@123@192.168.1.$i:554/1/1?transmode=unicast&profile=va
          roles:
            - detect
            - rtmp
    detect:
      width: 1920
      height: 1080
      fps: 5
EOF
done

# Create Docker Compose file for Frigate
cat <<EOF | sudo tee $FRIGATE_CONFIG_PATH/docker-compose.yml > /dev/null
version: '3.9'
services:
  frigate:
    container_name: frigate
    image: ghcr.io/blakeblackshear/frigate:stable
    runtime: nvidia
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]
    restart: unless-stopped
    shm_size: "64mb"
    privileged: true
    environment:
      - FRIGATE_RTSP_PASSWORD=$PASSWORD
    volumes:
      - $FRIGATE_CONFIG_PATH/config.yml:/config/config.yml:ro
      - /etc/localtime:/etc/localtime:ro
      - /media/frigate:/media/frigate
      - type: tmpfs
        target: /tmp/cache
    ports:
      - "5000:5000"
      - "8554:8554"
      - "1935:1935"
EOF

# Start Frigate container
docker compose -f $FRIGATE_CONFIG_PATH/docker-compose.yml up -d

echo "Frigate installation and configuration complete. Access it at http://localhost:5000 with username $USERNAME and password $PASSWORD."
