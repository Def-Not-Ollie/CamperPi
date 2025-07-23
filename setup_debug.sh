#!/bin/bash
set -euxo pipefail

USER=$(whoami)
HA_CONFIG_DIR="/home/$USER/homeassistant"

echo "Starting CamperPi setup as $USER..."

echo "Unblocking Wi-Fi..."
rfkill unblock wifi || true

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
  dhcpcd5 rfkill

echo "Enabling and starting dhcpcd..."
systemctl enable dhcpcd
systemctl start dhcpcd

echo "Enabling Docker..."
systemctl enable docker
systemctl start docker

echo "Setting up Home Assistant..."
mkdir -p "$HA_CONFIG_DIR"
chown "$USER:$USER" "$HA_CONFIG_DIR"
if docker ps -a --format '{{.Names}}' | grep -q '^homeassistant$'; then
    echo "Home Assistant container exists. Skipping creation."
else
    echo "Creating Home Assistant container..."
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

systemctl daemon-reload
systemctl enable home-assistant

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

systemctl daemon-reload
systemctl enable kodi

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
echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' | tee -a /etc/default/hostapd

echo "Configuring static IP for wlan0..."
if ! grep -q "interface wlan0" /etc/dhcpcd.conf; then
  echo -e "\ninterface wlan0\n    static ip_address=192.168.50.1/24\n    nohook wpa_supplicant" | tee -a /etc/dhcpcd.conf
fi

echo "Configuring dnsmasq..."
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig 2>/dev/null || true
tee /etc/dnsmasq.conf > /dev/null <<EOF
interface=wlan0
dhcp-range=192.168.50.2,192.168.50.20,255.255.255.0,24h
EOF

systemctl unmask hostapd
systemctl enable hostapd dnsmasq
systemctl restart hostapd
systemctl restart dnsmasq

systemctl is-active hostapd && echo "✅ hostapd running" || echo "❌ hostapd NOT running"
systemctl is-active dnsmasq && echo "✅ dnsmasq running" || echo "❌ dnsmasq NOT running"

ip_addr="192.168.50.1"
echo "Hotspot IP: $ip_addr"

# Add NAT rule if not present
if ! iptables -t nat -C POSTROUTING -o wlan0 -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
fi
netfilter-persistent save

echo "Setup complete. Rebooting now. Access Home Assistant at http://$ip_addr:8123"

sleep 2
reboot
