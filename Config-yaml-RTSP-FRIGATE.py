import yaml

# Configuration file path
CONFIG_FILE_PATH = "config.yml"

# MQTT and Detector settings
config = {
    "mqtt": {
        "host": "127.0.0.1"
    },
    "detectors": {
        "coral": {
            "type": "edgetpu",
            "device": "usb"
        }
    },
    "database": {
        "path": "/db/frigate.db"
    },
    "cameras": {}
}

# Base URL and credentials
BASE_RTSP_URL = "rtsp://admin:admin@123@192.168.1.{}.554/1/1?transmode=unicast&profile=va"

# IP Range
START_IP = 10
END_IP = 54

# Camera configuration parameters
CAMERA_WIDTH = 1280
CAMERA_HEIGHT = 720
OBJECTS_TO_TRACK = ["person", "car"]

# Generate camera configurations
for ip_suffix in range(START_IP, END_IP + 1):
    camera_name = f"camera_{ip_suffix}"
    rtsp_url = BASE_RTSP_URL.format(ip_suffix)
    config["cameras"][camera_name] = {
        "ffmpeg": {
            "inputs": [
                {
                    "path": rtsp_url,
                    "roles": ["detect"]
                }
            ]
        },
        "detect": {
            "width": CAMERA_WIDTH,
            "height": CAMERA_HEIGHT
        },
        "objects": {
            "track": OBJECTS_TO_TRACK
        }
    }

# Write configuration to YAML file
with open(CONFIG_FILE_PATH, "w") as file:
    yaml.dump(config, file, default_flow_style=False)

print(f"Frigate configuration file '{CONFIG_FILE_PATH}' generated successfully.")
