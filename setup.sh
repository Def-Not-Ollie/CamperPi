#!/bin/bash

set -e  # Stop script on error

# Variables
USER="admin"
HA_DIR="/home/$USER/homeassistant"
VENV_DIR="$HA_DIR/venv"
PYTHON_VERSION="3.11"

# Update and install dependencies
echo "Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3 python3-pip python3-venv python3-dev libffi-dev libssl-dev libjpeg-dev zlib1g-dev autoconf build-essential \
    libopenjp2-7-dev libtiff5 libturbojpeg0-dev tzdata ffmpeg

# Create user and set permissions
if ! id "$USER" &>/dev/null; then
    echo "Creating user $USER..."
    sudo useradd -rm "$USER" -G dialout,gpio,i2c
fi

# Create and set up Home Assistant directory
echo "Setting up Home Assistant environment..."
sudo -u $USER mkdir -p $HA_DIR
cd $HA_DIR

# Create and activate virtual environment
sudo -u $USER python3 -m venv $VENV_DIR
source $VENV_DIR/bin/activate

# Upgrade pip and install Home Assistant
echo "Installing Home Assistant..."
pip install --upgrade pip wheel
pip install homeassistant

# Create systemd service file
echo "Creating Home Assistant service..."
SERVICE_FILE="/etc/systemd/system/home-assistant.service"
echo "[Unit]
Description=Home Assistant
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=$VENV_DIR/bin/hass -c $HA_DIR
Restart=always

[Install]
WantedBy=multi-user.target" | sudo tee $SERVICE_FILE

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl enable home-assistant
sudo systemctl start home-assistant

echo "Installation complete! Home Assistant is now running."
