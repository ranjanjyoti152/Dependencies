#!/bin/bash

# Define the configuration file path
CONFIG_FILE="config.yml"
TARGET_DIR="/opt/frigate"

# Check if config.yml exists
if [ -f "$CONFIG_FILE" ]; then
    echo "Moving $CONFIG_FILE to $TARGET_DIR"
    sudo mv "$CONFIG_FILE" "$TARGET_DIR/config.yml"
    echo "Configuration file successfully moved to $TARGET_DIR."
else
    echo "Configuration file $CONFIG_FILE not found."
    exit 1
fi
