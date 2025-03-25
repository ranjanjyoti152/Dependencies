# Step 1: Clean Up Existing Frigate Installation

# Stop and Remove Containers:
cd ~/frigate
docker-compose down

# Remove Frigate Images:

docker rmi ghcr.io/blakeblackshear/frigate:stable-tensorrt

# Delete Frigate Directory:

cd ~
rm -rf ~/frigate

# Optional Cleanup:

docker system prune -a --volumes

# Step 2: Reconfigure with TensorFlow GPU and YOLOv5
# Step 2.1: Create Directory Structure

mkdir -p ~/frigate/config/custom_model ~/frigate/storage
cd ~/frigate

# Step 2.2: Create a Custom Dockerfile

# Since we’re starting with tensorflow/tensorflow:latest-gpu, we’ll add Frigate and YOLOv5 support. Create ~/frigate/Dockerfile:


# Start with TensorFlow GPU image (includes CUDA, cuDNN, and NVIDIA runtime)
FROM tensorflow/tensorflow:latest-gpu

# Install system dependencies for Frigate
RUN apt-get update && apt-get install -y \
    python3-pip \
    ffmpeg \
    libopenblas-dev \
    libatlas-base-dev \
    liblapack-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies for Frigate
RUN pip3 install --upgrade pip
RUN pip3 install \
    numpy \
    opencv-python \
    pyyaml \
    requests \
    scipy \
    tensorrt  # For NVIDIA GPU detection with YOLOv5

# Install Frigate
RUN pip3 install frigate

# Copy custom YOLOv5 model
COPY config/custom_model/ /models/

# Set working directory
WORKDIR /config

# Expose Frigate ports
EXPOSE 5000 8971 1935

# Entry point for Frigate
CMD ["frigate"]

Notes:
This assumes your YOLOv5 model (best.engine or best.pt) will be in ~/frigate/config/custom_model/.
TensorRT is added for YOLOv5 detection (Frigate’s default for NVIDIA GPUs).
TensorFlow GPU is included but not directly used by Frigate unless you customize detection logic.

# Place your best.engine (or best.pt) in ~/frigate/config/custom_model/.

# Step 2.4: Create docker-compose.yml

# Create ~/frigate/docker-compose.yml:

version: "3.9"
services:
  frigate:
    build: .
    container_name: frigate
    runtime: nvidia  # NVIDIA GPU for TensorRT
    privileged: true  # Access to /dev/dri and GPU
    environment:
      - FRIGATE_RTSP_PASSWORD=your_password
    volumes:
      - ./config:/config
      - ./storage:/media/frigate
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "5000:5000"
      - "8971:8971"
      - "1935:1935"
    devices:
      - /dev/dri:/dev/dri  # Intel iGPU for decoding
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    restart: unless-stopped


# Step 2.5: Configure config.yml with Your 22 Classes

Create ~/frigate/config/config.yml:

detectors:
  tensorrt:
    type: tensorrt
    device: 0  # NVIDIA GPU for YOLOv5
    model:
      path: /models/best.engine  # Use best.pt if not exported
      width: 640  # From multi-scale, adjust if needed
      height: 640
      input_tensor: nchw
      input_channels: 3
      num_classes: 22
      labels:
        - ambulance
        - auto
        - bicycle
        - book
        - bottle
        - bus
        - car
        - chair
        - fire
        - gun
        - helmet
        - jeep
        - keyboard
        - mobile-phone
        - monitor
        - motorcycle
        - mouse
        - person
        - smoke
        - telephone
        - traffic light
        - truck

mqtt:
  enabled: false
cameras:
  my_camera:
    ffmpeg:
      inputs:
        - path: rtsp://username:password@camera_ip:554/stream
          roles:
            - detect
      hwaccel_args: preset-intel-qsv-h264  # Intel iGPU decoding
    detect:
      enabled: true
      width: 1280
      height: 720


# Step 2.6: Build and Start

cd ~/frigate
docker-compose up -d --build


