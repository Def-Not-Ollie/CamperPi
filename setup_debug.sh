#!/bin/bash
set -euxo pipefail

USER=$(whoami)
HA_CONFIG_DIR="/home/$USER/homeassistant"
IP_ADDR="192.168.50.1"

echo "Starting CamperPi setup as $USER..."

# --- System Prep ---
echo "Syncing time..."
timedatectl set-ntp on
systemctl restart systemd-timesyncd

echo "Preconfiguring iptables-persistent..."
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections

echo "Installing packages..."
DEBIAN_FRONTEND=noninteractive apt update
DEBIAN_FRONTEND=noninteractive apt full-upgrade -y
DEBIAN_FRONTEND=noninteractive apt install -y \
  kodi docker.io docker-compose \
  hostapd dnsmasq iptables-persistent netfilter-persistent \
  dhcpcd5

echo "Enabling and starting required services..."
systemctl enable --now docker
systemctl enable --now dhcpcd

# --- Home Assistant Setup ---
echo "Setting up Home Assistant..."
mkdir -p "$HA_CONFIG_DIR"
chown "$USER:$USER" "$HA_CONFIG_DIR"

if ! docker ps -a --format '{{.Names}}' | grep -q '^homeassistant$'; then
  docker create --name homeassistant --restart=unless-stopped --privileged \
    -v "$HA_CONFIG_DIR:/config" --network=host \
    ghcr.io/home-assistant/home-assistant:stable
fi

echo "Creating Home Assistant service..."
tee /etc/systemd/system/home-assistant.service > /dev/null <<EOF
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

# --- Kodi Service ---
echo "Creating Kodi service..."
tee /etc/systemd/system/kodi.service > /dev/null <<EOF
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

# Reload once for both new services
systemctl daemon-reload
systemctl enable home-assistant kodi

# --- Wi-Fi Access Point ---
echo "Setting up Wi-Fi Access Point..."
tee /etc/hostapd/hostapd.conf > /dev/null <<EOF
interface=wlan0
driver=nl80211
ssid=CamperPi
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=CamperPi
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

sed -i '/^DAEMON_CONF=/d' /etc/default/hostapd
echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >> /etc/default/hostapd

echo "Configuring static IP for wlan0..."
if ! grep -q "interface wlan0" /etc/dhcpcd.conf; then
  cat <<EOF >> /etc/dhcpcd.conf

interface wlan0
    static ip_address=${IP_ADDR}/24
    nohook wpa_supplicant
EOF
fi

echo "Configuring dnsmasq..."
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig 2>/dev/null || true
tee /etc/dnsmasq.conf > /dev/null <<EOF
interface=wlan0
dhcp-range=192.168.50.2,192.168.50.20,255.255.255.0,24h
EOF

systemctl unmask hostapd
systemctl enable --now hostapd dnsmasq

# --- Network Routing ---
echo "Configuring NAT routing..."
if ! iptables -t nat -C POSTROUTING -o wlan0 -j MASQUERADE 2>/dev/null; then
  iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
fi
netfilter-persistent save

# --- Summary ---
systemctl is-active hostapd && echo "✅ hostapd running" || echo "❌ hostapd NOT running"
systemctl is-active dnsmasq && echo "✅ dnsmasq running" || echo "❌ dnsmasq NOT running"
echo "Hotspot IP: http://$IP_ADDR:8123"

echo "Setup complete. Rebooting now..."
sleep 2
reboot
