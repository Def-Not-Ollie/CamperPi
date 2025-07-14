#!/bin/bash
set -e

# Variables
USER="admin"
HOME_DIR="/home/$USER"
HA_CONFIG_DIR="$HOME_DIR/homeassistant"

# 1. Sync Time
echo "Syncing time..."
sudo timedatectl set-ntp on
sudo systemctl restart systemd-timesyncd

# 2. Update & Install Required Packages
echo "Updating system and installing packages..."
sudo apt update
sudo apt upgrade -y
sudo apt install -y kodi docker.io docker-compose

# 3. Set Up Kodi to Start on Boot
echo "Setting up Kodi systemd service..."

sudo tee /etc/systemd/system/kodi.service > /dev/null <<EOF
[Unit]
Description=Kodi Media Center
After=network.target

[Service]
User=$USER
Group=$USER
Type=simple
ExecStart=/usr/bin/kodi --standalone
Restart=unless-stopped
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable kodi
sudo systemctl start kodi

# 4. Install & Set Up Home Assistant in Docker
echo "Setting up Home Assistant in Docker..."

mkdir -p "$HA_CONFIG_DIR"

sudo docker run -d \
  --name homeassistant \
  --restart=unless-stopped \
  --privileged \
  -v "$HA_CONFIG_DIR:/config" \
  --network=host \
  ghcr.io/home-assistant/home-assistant:stable

# 5. Set Up Home Assistant to Start on Boot
echo "Setting up Home Assistant systemd service..."

sudo tee /etc/systemd/system/home-assistant.service > /dev/null <<EOF
[Unit]
Description=Home Assistant
After=network.target docker.service
Requires=docker.service

[Service]
User=$USER
Group=$USER
ExecStart=/usr/bin/docker start homeassistant
ExecStop=/usr/bin/docker stop homeassistant
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable home-assistant
sudo systemctl start home-assistant

# 6. Enable Docker to Start on Boot
echo "Enabling Docker to start on boot..."
sudo systemctl enable docker
sudo systemctl start docker

# 7. Reboot & Verify
echo "Setup complete. Rebooting system now..."
sudo reboot
