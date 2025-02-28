#!/bin/bash

set -e  # Stop script on any error
set -x  # Show all executed commands (for debugging)

echo "Updating system time to prevent repository errors..."
sudo date -s "$(curl -s --head http://google.com | grep '^Date:' | cut -d' ' -f3-6)Z"

echo "Updating package lists..."
sudo apt update || sudo apt-get update

echo "Upgrading system packages..."
sudo apt upgrade -y

echo "Installing required dependencies..."
sudo apt install -y \
    python3 python3-pip python3-venv \
    git wget curl \
    avahi-daemon \
    libtiff6  # Replaced libtiff5 with libtiff6 (correct for Debian Bookworm)

echo "Setting up Home Assistant..."
python3 -m venv homeassistant
source homeassistant/bin/activate
pip install --upgrade pip
pip install homeassistant

echo "Creating Home Assistant service..."
cat <<EOF | sudo tee /etc/systemd/system/home-assistant.service
[Unit]
Description=Home Assistant
After=network.target

[Service]
Type=simple
User=admin
ExecStart=/home/admin/homeassistant/bin/hass
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "Enabling Home Assistant to start on boot..."
sudo systemctl enable home-assistant
sudo systemctl start home-assistant

echo "Installation complete. Rebooting..."
sudo reboot
