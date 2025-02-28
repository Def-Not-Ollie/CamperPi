#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Define installation directories
HASS_DIR="/home/admin/homeassistant"
VENV_DIR="$HASS_DIR/venv"

echo "📌 Updating system..."
sudo apt update && sudo apt upgrade -y

echo "📌 Installing dependencies..."
sudo apt install -y \
    python3 python3-venv python3-pip \
    libffi-dev libssl-dev libjpeg-dev zlib1g-dev \
    autoconf build-essential libopenjp2-7 libtiff5 \
    libturbojpeg0-dev tzdata kodi

echo "📌 Setting up Home Assistant..."
sudo mkdir -p "$HASS_DIR"
sudo chown admin:admin "$HASS_DIR"

python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

echo "📌 Upgrading pip and installing Home Assistant..."
pip install --upgrade pip setuptools wheel
pip install homeassistant==2024.2.0
pip install acme==2.8.0 cryptography==42.0.5 pyOpenSSL==24.0.0 josepy==1.15.0

echo "📌 Creating Home Assistant service..."
sudo tee /etc/systemd/system/home-assistant.service > /dev/null <<EOL
[Unit]
Description=Home Assistant
After=network.target

[Service]
Type=simple
User=admin
ExecStart=$VENV_DIR/bin/hass --config $HASS_DIR
Restart=always

[Install]
WantedBy=multi-user.target
EOL

echo "📌 Enabling and starting Home Assistant..."
sudo systemctl daemon-reload
sudo systemctl enable home-assistant
sudo systemctl start home-assistant

echo "📌 Enabling Kodi to start at boot..."
sudo systemctl enable kodi

echo "✅ Setup complete! Access Home Assistant at: http://your-raspberry-pi-ip:8123"
echo "🎬 Kodi can be started manually with: kodi"
