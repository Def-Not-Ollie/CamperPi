#!/bin/bash
set -euxo pipefail

USER=$(whoami)
HA_CONFIG_DIR="/home/$USER/homeassistant"

echo "Starting CamperPi setup as $USER..."

echo "Syncing time..."
sudo timedatectl set-ntp on
sudo systemctl restart systemd-timesyncd

echo "Preconfiguring iptables-persistent..."
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections

echo "Installing packages..."
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y kodi docker.io docker-compose iptables-persistent netfilter-persistent

echo "Enabling Docker..."
sudo systemctl enable docker
sudo systemctl start docker

echo "Setting up Home Assistant..."
mkdir -p "$HA_CONFIG_DIR"
if sudo docker ps -a --format '{{.Names}}' | grep -q '^homeassistant$'; then
    echo "Home Assistant container exists. Skipping creation."
else
    echo "Creating and starting Home Assistant container..."
    sudo docker run -d --name homeassistant --restart=unless-stopped --privileged -v "$HA_CONFIG_DIR:/config" --network=host ghcr.io/home-assistant/home-assistant:stable
fi

echo "Creating Home Assistant service..."
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

echo "Creating Kodi service..."
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

echo "Setup complete. Rebooting..."
sudo reboot
