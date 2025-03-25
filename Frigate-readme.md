# Final Frigate Configuration with Multi-Scale YOLOv5

mkdir -p ~/frigate/config/custom_model ~/frigate/storage
cd ~/frigate


# Step 2: docker-compose.yml

version: "3.9"
services:
  frigate:
    image: ghcr.io/blakeblackshear/frigate:stable-tensorrt
    container_name: frigate
    runtime: nvidia
    privileged: true
    environment:
      - FRIGATE_RTSP_PASSWORD=your_password
    volumes:
      - ./config:/config
      - ./storage:/media/frigate
      - /etc/localtime:/etc/localtime:ro
      - ./config/custom_model:/models
    ports:
      - "5000:5000"
      - "8971:8971"
      - "1935:1935"
    devices:
      - /dev/dri:/dev/dri
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    restart: unless-stopped

# Step 4: Updated config.yml with Multi-Scale Consideration


# Update ~/frigate/config/config.yml:


detectors:
  tensorrt:
    type: tensorrt
    device: 0  # NVIDIA GPU for YOLOv5 detection
    model:
      path: /models/best.engine  # Use best.pt if not exported
      width: 640  # Assuming 640x640 from multi-scale training
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
      width: 1280  # Camera resolution
      height: 720




# Step 5: Start Frigate

cd ~/frigate
docker-compose up -d