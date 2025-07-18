#!/bin/bash
set -e

# Auto-detect current user
USER=$(whoami)
HOME_DIR="/home/$USER"
HA_CONFIG_DIR="$HOME_DIR/homeassistant"

echo "Starting CamperPi setup as $USER..."

# Sync time
echo "Syncing time..."
sudo timedatectl set-ntp on
sudo systemctl restart systemd-timesyncd

# Pre-seed iptables-persistent to avoid prompt
echo "Preconfiguring iptables-persistent package to auto-save rules..."
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections

# Update & install required packages
echo "Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y kodi docker.io docker-compose hostapd dnsmasq iptables-persistent netfilter-persistent

# Stop potential blockers for wlan0
echo "Stopping wpa_supplicant and NetworkManager to free wlan0..."
sudo systemctl stop wpa_supplicant
sudo systemctl stop NetworkManager

# Reset wlan0 interface
echo "Resetting wlan0 interface..."
sudo ip link set wlan0 down
sudo ip link set wlan0 up

# Enable Docker
echo "Enabling Docker..."
sudo systemctl enable docker
sudo systemctl start docker

# Home Assistant container setup
echo "Setting up Home Assistant in Docker..."
mkdir -p "$HA_CONFIG_DIR"

if sudo docker ps -a --format '{{.Names}}' | grep -q '^homeassistant$'; then
    echo "Home Assistant container already exists. Starting it..."
    sudo docker start homeassistant
else
    echo "Creating and starting Home Assistant container..."
    sudo docker run -d \
      --name homeassistant \
      --restart=unless-stopped \
      --privileged \
      -v "$HA_CONFIG_DIR:/config" \
      --network=host \
      ghcr.io/home-assistant/home-assistant:stable
fi

# Home Assistant systemd service
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
sudo systemctl start home-assistant

# Kodi systemd service (enable only, delay until reboot)
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

# Setup Wi-Fi Access Point
echo "Setting up Wi-Fi Access Point on wlan0..."
sudo tee /etc/hostapd/hostapd.conf > /dev/null <<EOF
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

# Replace DAEMON_CONF line cleanly (avoid duplicates)
sudo sed -i '/^DAEMON_CONF=/d' /etc/default/hostapd
echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' | sudo tee -a /etc/default/hostapd

# Set static IP for wlan0
echo "Configuring static IP for wlan0..."
echo -e "\ninterface wlan0\n    static ip_address=192.168.50.1/24\n    nohook wpa_supplicant" | sudo tee -a /etc/dhcpcd.conf

# Configure dnsmasq
echo "Configuring dnsmasq..."
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig || true
sudo tee /etc/dnsmasq.conf > /dev/null <<EOF
interface=wlan0
dhcp-range=192.168.50.2,192.168.50.20,255.255.255.0,24h
EOF

# Enable hostapd and dnsmasq
sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq

# Setup basic NAT for Ethernet and wlan0
echo "Setting up NAT between eth0 and wlan0..."
sudo iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
sudo netfilter-persistent save

# Final message and wait for confirmation before reboot
echo ""
echo "======================================"
echo "  Setup complete!                      "
echo "  Wi-Fi Access Point details:         "
echo "    SSID: CamperPi                    "
echo "    Password: CamperPi                 "
echo "  Kodi will start on next reboot.     "
echo "  Home Assistant is running now.      "
echo "  Access Home Assistant at:           "
echo "    http://192.168.50.1:8123"
echo "======================================"
echo ""
read -p "Press ENTER to reboot now or CTRL+C to cancel..."

sudo reboot
