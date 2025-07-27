#!/bin/bash
set -euxo pipefail

# Check for root or sudo
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

echo "Starting setup for Raspberry Pi OS Lite 64-bit..."

USER=${SUDO_USER:-$(whoami)}
HA_CONFIG_DIR="/home/$USER/homeassistant"

# Ensure HA config dir exists and is writable by USER
if [[ ! -d "$HA_CONFIG_DIR" ]]; then
  mkdir -p "$HA_CONFIG_DIR"
fi
chown "$USER:$USER" "$HA_CONFIG_DIR"

# Get system timezone
TZ=$(timedatectl show -p Timezone --value)
echo "Using timezone: $TZ"

# --- Install Kodi ---
echo "Installing Kodi..."
apt update -y
if ! apt install -y kodi; then
  echo "Error: Kodi installation failed."
  exit 1
fi
usermod -aG cdrom,audio,render,video,plugdev,users,dialout,dip,input "$USER"

# --- Install Docker Engine ---
echo "Installing Docker Engine..."
apt-get remove -y docker docker-engine docker.io containerd runc || true
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
if ! curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
  echo "Error: Failed to download Docker GPG key."
  exit 1
fi
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
  echo "Error: Docker installation failed."
  exit 1
fi
systemctl enable docker
systemctl start docker
usermod -aG docker "$USER"

# --- Setup Home Assistant container ---
echo "Setting up Home Assistant container..."
docker_args=( 
  --name homeassistant
  --restart=unless-stopped
  --privileged
  -e TZ="$TZ"
  -v "$HA_CONFIG_DIR":/config
  -v /run/dbus:/run/dbus:ro
  --network=host
)

if ! docker ps -a --format '{{.Names}}' | grep -q '^homeassistant$'; then
  if ! docker run -d "${docker_args[@]}" ghcr.io/home-assistant/home-assistant:stable; then
    echo "Error: Home Assistant container setup failed."
    exit 1
  fi
fi

# --- Create Kodi systemd service ---
echo "Creating Kodi systemd service..."
tee /etc/systemd/system/kodi.service > /dev/null <<EOF
[Unit]
Description=Kodi Media Center
After=network.target

[Service]
User=$USER
Group=$USER
Environment="HOME=/home/$USER"
Type=simple
ExecStart=/usr/bin/kodi --standalone
Restart=unless-stopped
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kodi

echo "Setup complete."
read -p "Reboot now? (y/n): " confirm && [[ \$confirm == [yY] ]] && reboot
