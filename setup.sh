#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

# Ensure script runs as root
if [[ $EUID -ne 0 ]]; then
  echo "Run as root or with sudo."
  exit 1
fi

echo "Starting setup for Raspberry Pi OS Lite 64-bit (headless)..."

# Ensure sudo exists
apt-get update -y
apt-get install -y sudo

USER=${SUDO_USER:-$(whoami)}
HA_CONFIG_DIR="/home/$USER/homeassistant"

# Ensure HA config dir exists and is writable
mkdir -p "$HA_CONFIG_DIR"
chown "$USER:$USER" "$HA_CONFIG_DIR"

# Get timezone
TZ=$(timedatectl show -p Timezone --value || echo "UTC")
echo "Using timezone: $TZ"

# --- Install Kodi ---
echo "Installing Kodi..."
apt-get install -y kodi
usermod -aG cdrom,audio,render,video,plugdev,users,dialout,dip,input "$USER"

# --- Install Docker ---
echo "Installing Docker..."
apt-get remove -y docker docker-engine docker.io containerd runc || true
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker
usermod -aG docker "$USER"

# --- Home Assistant Container ---
echo "Setting up Home Assistant..."
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
  docker run -d "${docker_args[@]}" ghcr.io/home-assistant/home-assistant:stable
fi

# --- Kodi systemd service ---
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

echo "Setup complete. Rebooting in 5 seconds..."
sleep 5
reboot
