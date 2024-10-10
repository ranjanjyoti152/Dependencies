import time
import pyaudio
import numpy as np
import subprocess

# Function to get the current system volume on macOS
def get_system_volume():
    volume = subprocess.run(
        ["osascript", "-e", "output volume of (get volume settings)"],
        capture_output=True,
        text=True,
    )
    return int(volume.stdout.strip()) / 100  # Normalize to a 0-1 scale

# Function to set the system volume on macOS (input as percentage 0-100)
def set_system_volume(volume_level):
    volume_percentage = int(volume_level * 100)
    subprocess.run(["osascript", "-e", f"set volume output volume {volume_percentage}"])

# Function to reduce volume to 20%
def reduce_volume(target_level=0.20):
    set_system_volume(target_level)

# Function to restore volume to previous level
def restore_volume(previous_level):
    set_system_volume(previous_level)

# Initialize PyAudio to listen for sound input
p = pyaudio.PyAudio()
stream = p.open(format=pyaudio.paInt16, channels=1, rate=44100, input=True, frames_per_buffer=1024)

# Get the initial system volume
previous_volume = get_system_volume()

try:
    print("Monitoring for conversation. Press Ctrl+C to stop.")

    while True:
        data = np.frombuffer(stream.read(1024), dtype=np.int16)
        sound_level = np.abs(data).mean()  # Calculate the average sound level

        # Check if sound level crosses a threshold indicating conversation
        if sound_level > 500:  # You can adjust the threshold based on sensitivity
            print("Conversation detected. Reducing volume.")
            reduce_volume()
        else:
            print("No conversation. Restoring volume.")
            restore_volume(previous_volume)

        time.sleep(1)

except KeyboardInterrupt:
    print("Stopping monitoring.")

finally:
    stream.stop_stream()
    stream.close()
    p.terminate()
