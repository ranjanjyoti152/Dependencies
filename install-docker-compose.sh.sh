#!/bin/bash

# Function to display error messages and exit
error_exit() {
  echo "Error: $1" >&2
  exit 1
}

# Update package information
sudo apt-get update || error_exit "Failed to update package list."

# Install dependencies if not already installed
sudo apt-get install -y curl jq || error_exit "Failed to install required packages."

# Fetch the latest version of Docker Compose
COMPOSE_LATEST=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name')
if [[ -z "$COMPOSE_LATEST" || "$COMPOSE_LATEST" == "null" ]]; then
  error_exit "Could not fetch the latest Docker Compose version."
fi

# Define the download URL and destination
COMPOSE_URL="https://github.com/docker/compose/releases/download/$COMPOSE_LATEST/docker-compose-$(uname -s)-$(uname -m)"
COMPOSE_DEST="/usr/local/bin/docker-compose"

# Download Docker Compose
sudo curl -L "$COMPOSE_URL" -o "$COMPOSE_DEST" || error_exit "Failed to download Docker Compose."

# Make Docker Compose executable
sudo chmod +x "$COMPOSE_DEST" || error_exit "Failed to make Docker Compose executable."

# Verify the installation
INSTALLED_VERSION=$(docker-compose --version 2>/dev/null)
if [[ $? -eq 0 ]]; then
  echo "Docker Compose installed successfully: $INSTALLED_VERSION"
else
  error_exit "Docker Compose installation failed."
fi

# Optional: Provide instructions to the user
echo "To start using Docker Compose, run 'docker-compose --version' to confirm the installation."
