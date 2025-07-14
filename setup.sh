#!/bin/bash
set -e

USERNAME="admin"
HASS_DIR="/home/$USERNAME/homeassistant"
WIFI_SSID="CamperPi"
WIFI_PASS="CamperPi"
WIFI_IFACE="wlan0"
WIFI_IP="192.168.10.1"
WIFI_SUBNET="192.168.10.0/24"

# 1. Sync time
echo "🕒 Syncing time..."
timedatectl set-ntp on
systemctl restart systemd-timesyncd

# 2. Update & install packages
echo "📦 Updating and installing packages..."
apt update && apt upgrade -y
apt install -y kodi docker.io docker-compose hostapd dnsmasq netfilter-persistent iptables-persistent git

# 3. Setup Kodi systemd service
echo "🎬 Setting up Kodi service..."
cat > /etc/systemd/system/kodi.service <<EOF
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

systemctl daemon-reload
systemctl enable kodi
systemctl start kodi

# 4. Setup Home Assistant in Docker
echo "🏠 Setting up Home Assistant..."
mkdir -p "$HASS_DIR"
chown $USERNAME:$USERNAME "$HASS_DIR"

docker pull ghcr.io/home-assistant/home-assistant:stable

docker run -d \
  --name homeassistant \
  --restart=unless-stopped \
  --privileged \
  -v "$HASS_DIR":/config \
  --network=host \
  ghcr.io/home-assistant/home-assistant:stable

# 5. Setup Home Assistant systemd service
cat > /etc/systemd/system/home-assistant.service <<EOF
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

systemctl daemon-reload
systemctl enable home-assistant
systemctl start home-assistant

# 6. Enable Docker on boot
echo "🐳 Enabling Docker..."
systemctl enable docker
systemctl start docker

# 7. Configure Wi-Fi hotspot
echo "📡 Configuring Wi-Fi hotspot on $WIFI_IFACE..."

# Setup static IP for wlan0
grep -q "^interface $WIFI_IFACE" /etc/dhcpcd.conf || cat >> /etc/dhcpcd.conf <<EOF

interface $WIFI_IFACE
    static ip_address=$WIFI_IP/24
    nohook wpa_supplicant
EOF

# Configure dnsmasq
cat > /etc/dnsmasq.conf <<EOF
interface=$WIFI_IFACE
dhcp-range=192.168.10.10,192.168.10.100,255.255.255.0,24h
EOF

# Configure hostapd
cat > /etc/hostapd/hostapd.conf <<EOF
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

# Enable hostapd config
sed -i 's|#DAEMON_CONF="".*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

systemctl unmask hostapd
systemctl enable hostapd
systemctl enable dnsmasq
systemctl restart dhcpcd
systemctl restart dnsmasq
systemctl restart hostapd

# Enable IP forwarding
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

# Setup NAT for wlan0 via eth0
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
netfilter-persistent save

echo "✅ Setup complete! Rebooting in 5 seconds..."
sleep 5
reboot
