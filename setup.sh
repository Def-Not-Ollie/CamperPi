#!/bin/bash
set -e

USERNAME=$(whoami)
HASS_DIR="/home/$USERNAME/homeassistant"
WIFI_SSID="CamperPi"
WIFI_PASS="CamperPi"
WIFI_IFACE="wlan0"
WIFI_IP="192.168.10.1"
WIFI_SUBNET="192.168.10.0/24"

echo "Running as user: $USERNAME"

# 1. Sync system time
echo "🕒 Syncing time..."
sudo timedatectl set-ntp on
sudo systemctl restart systemd-timesyncd

# 2. Update & install packages
echo "📦 Updating and installing packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y kodi docker.io docker-compose hostapd dnsmasq netfilter-persistent iptables-persistent git

# 3. Setup Kodi systemd service
echo "🎬 Setting up Kodi service..."
sudo tee /etc/systemd/system/kodi.service > /dev/null <<EOF
[Unit]
Description=Kodi Media Center
After=network.target

[Service]
User=$USERNAME
Group=$USERNAME
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

# 4. Setup Home Assistant in Docker
echo "🏠 Setting up Home Assistant..."
mkdir -p "$HASS_DIR"
sudo chown $USERNAME:$USERNAME "$HASS_DIR"

sudo docker pull ghcr.io/home-assistant/home-assistant:stable

sudo docker run -d \
  --name homeassistant \
  --restart=unless-stopped \
  --privileged \
  -v "$HASS_DIR":/config \
  --network=host \
  ghcr.io/home-assistant/home-assistant:stable

# 5. Setup Home Assistant systemd service
sudo tee /etc/systemd/system/home-assistant.service > /dev/null <<EOF
[Unit]
Description=Home Assistant
After=network.target docker.service
Requires=docker.service

[Service]
User=$USERNAME
Group=$USERNAME
ExecStart=/usr/bin/docker start -a homeassistant
ExecStop=/usr/bin/docker stop homeassistant
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable home-assistant
sudo systemctl start home-assistant

# 6. Enable and start Docker service
echo "🐳 Enabling Docker..."
sudo systemctl enable docker
sudo systemctl start docker

# 7. Configure Wi-Fi hotspot
echo "📡 Configuring Wi-Fi hotspot on $WIFI_IFACE..."

# Setup static IP for wlan0
if ! grep -q "^interface $WIFI_IFACE" /etc/dhcpcd.conf; then
  sudo tee -a /etc/dhcpcd.conf > /dev/null <<EOF

interface $WIFI_IFACE
    static ip_address=$WIFI_IP/24
    nohook wpa_supplicant
EOF
fi

# Configure dnsmasq
sudo tee /etc/dnsmasq.conf > /dev/null <<EOF
interface=$WIFI_IFACE
dhcp-range=192.168.10.10,192.168.10.100,255.255.255.0,24h
EOF

# Configure hostapd
sudo tee /etc/hostapd/hostapd.conf > /dev/null <<EOF
interface=$WIFI_IFACE
driver=nl80211
ssid=$WIFI_SSID
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$WIFI_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

sudo sed -i 's|#DAEMON_CONF="".*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq
sudo systemctl restart dhcpcd
sudo systemctl restart dnsmasq
sudo systemctl restart hostapd

# Enable IP forwarding
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -p

# Setup NAT for wlan0 via eth0 (if connected)
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo netfilter-persistent save

echo "✅ Setup complete! Rebooting in 5 seconds..."
sleep 5
sudo reboot
