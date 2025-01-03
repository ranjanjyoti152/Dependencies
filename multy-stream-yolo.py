import cv2
import numpy as np
import torch
from threading import Thread

# Load the YOLOv5 model
model = torch.hub.load('ultralytics/yolov5', 'yolov5s', pretrained=True)
model.conf = 0.5  # Confidence threshold

# Define your RTSP streams
streams = [
    "rtsp://stream1",
    "rtsp://stream2",
    "rtsp://stream3",
    "rtsp://stream4"
]

# Define the grid layout (e.g., 2x2 for 4 streams)
rows = 2
cols = 2
window_name = "YOLOv5 Detection on Multiple Streams (CUDA Optimized)"

# Function to fetch and process frames from each stream
def fetch_and_detect(stream_url, frames_dict, idx):
    # Use OpenCV's VideoCapture with CUDA backend
    cap = cv2.VideoCapture(stream_url, cv2.CAP_FFMPEG)
    if not cap.isOpened():
        print(f"Failed to open stream: {stream_url}")
        return

    # Initialize CUDA objects
    cuda_frame = cv2.cuda_GpuMat()
    while True:
        ret, frame = cap.read()
        if not ret:
            frames_dict[idx] = np.zeros((480, 640, 3), dtype=np.uint8)
            continue

        # Upload frame to GPU
        cuda_frame.upload(frame)

        # Resize frame on GPU
        resized_cuda_frame = cv2.cuda.resize(cuda_frame, (640, 480))

        # Download resized frame back to CPU
        frame_resized = resized_cuda_frame.download()

        # Run YOLOv5 inference
        results = model(frame_resized)

        # Annotate frame with detection results
        annotated_frame = np.squeeze(results.render())
        frames_dict[idx] = annotated_frame

# Initialize frame storage
frames = {i: np.zeros((480, 640, 3), dtype=np.uint8) for i in range(len(streams))}

# Start threads to fetch and process frames
threads = []
for idx, stream in enumerate(streams):
    thread = Thread(target=fetch_and_detect, args=(stream, frames, idx))
    thread.daemon = True
    threads.append(thread)
    thread.start()

# Display the streams in a grid
while True:
    # Create a blank image for the grid
    h, w = 480, 640  # Resize each stream to 640x480
    grid_frame = np.zeros((rows * h, cols * w, 3), dtype=np.uint8)

    for idx, frame in frames.items():
        r, c = divmod(idx, cols)  # Get row and column in the grid
        grid_frame[r * h:(r + 1) * h, c * w:(c + 1) * w] = frame

    # Display the grid
    cv2.imshow(window_name, grid_frame)

    # Exit on 'q' key
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cv2.destroyAllWindows()
