#!/bin/bash
set -e

# Auto-detect current user
USER=$(whoami)
HOME_DIR="/home/$USER"
HA_CONFIG_DIR="$HOME_DIR/homeassistant"

echo "Starting CamperPi setup as $USER..."

# Unblock Wi-Fi
echo "Unblocking Wi-Fi..."
sudo rfkill unblock wifi

# Sync time
echo "Syncing time..."
sudo timedatectl set-ntp on
sudo systemctl restart systemd-timesyncd

# Pre-seed iptables-persistent
echo "Preconfiguring iptables-persistent..."
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections

# Update & install packages
echo "Installing packages..."
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y kodi docker.io docker-compose hostapd dnsmasq iptables-persistent netfilter-persistent

# Enable Docker
echo "Enabling Docker..."
sudo systemctl enable docker
sudo systemctl start docker

# Home Assistant setup (create but do not start)
echo "Setting up Home Assistant..."
mkdir -p "$HA_CONFIG_DIR"

if sudo docker ps -a --format '{{.Names}}' | grep -q '^homeassistant$'; then
    echo "Home Assistant container already exists. Skipping creation."
else
    echo "Creating Home Assistant container (will start on reboot)..."
    sudo docker create \
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

# Kodi systemd service
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

# Wi-Fi Access Point
echo "Setting up Wi-Fi Access Point..."
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

# Clean and apply hostapd default config
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

# Enable and restart services
sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq
sudo systemctl restart hostapd
sudo systemctl restart dnsmasq

# Check status
sudo systemctl is-active hostapd && echo "hostapd is running" || echo "hostapd NOT running"
sudo systemctl is-active dnsmasq && echo "dnsmasq is running" || echo "dnsmasq NOT running"

# Show network info
ip addr show wlan0 | grep 'inet '
rfkill list wlan

# Enable NAT
echo "Setting up NAT (eth0 → wlan0)..."
sudo iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
sudo netfilter-persistent save

# Final message
echo ""
echo "======================================"
echo "  Setup complete!                     "
echo "  Wi-Fi Access Point:                 "
echo "    SSID: CamperPi                    "
echo "    Password: CamperPi                "
echo "  Kodi & Home Assistant will start    "
echo "  after reboot. Access HA at:        "
echo "    http://192.168.50.1:8123         "
echo "======================================"
echo ""
read -p "Press ENTER to reboot now or CTRL+C to cancel..."

sudo reboot
