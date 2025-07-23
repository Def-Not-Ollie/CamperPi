#!/bin/bash
set -euxo pipefail

USER=$(whoami)
HA_CONFIG_DIR="/home/$USER/homeassistant"

echo "Starting CamperPi setup as $USER..."

echo "Syncing time..."
sudo timedatectl set-ntp on
sudo systemctl restart systemd-timesyncd

echo "Preconfiguring iptables-persistent..."
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections

echo "Installing packages..."
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y kodi docker.io docker-compose hostapd dnsmasq iptables-persistent netfilter-persistent

echo "Enabling Docker..."
sudo systemctl enable docker
sudo systemctl start docker

echo "Setting up Home Assistant..."
mkdir -p "$HA_CONFIG_DIR"
if sudo docker ps -a --format '{{.Names}}' | grep -q '^homeassistant$'; then
    echo "Home Assistant container exists. Skipping creation."
else
    echo "Creating and starting Home Assistant container..."
    sudo docker run -d --name homeassistant --restart=unless-stopped --privileged -v "$HA_CONFIG_DIR:/config" --network=host ghcr.io/home-assistant/home-assistant:stable
fi

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

echo "Configuring static IP and DHCP for wlan0 (Wi-Fi AP)..."
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

sudo sed -i '/^DAEMON_CONF=/d' /etc/default/hostapd
echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' | sudo tee -a /etc/default/hostapd

# Static IP for wlan0
if ! grep -q "^interface wlan0" /etc/dhcpcd.conf; then
  echo -e "\ninterface wlan0\n    static ip_address=192.168.50.1/24\n    nohook wpa_supplicant" | sudo tee -a /etc/dhcpcd.conf
fi

echo "Configuring static IP and DHCP for eth0 (local network)..."
# Static IP for eth0 (different subnet)
if ! grep -q "^interface eth0" /etc/dhcpcd.conf; then
  echo -e "\ninterface eth0\n    static ip_address=192.168.51.1/24\n    nohook wpa_supplicant" | sudo tee -a /etc/dhcpcd.conf
fi

echo "Configuring dnsmasq for wlan0 and eth0..."
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig 2>/dev/null || true
sudo tee /etc/dnsmasq.conf > /dev/null <<EOF
interface=wlan0
dhcp-range=192.168.50.2,192.168.50.20,255.255.255.0,24h

interface=eth0
dhcp-range=192.168.51.2,192.168.51.20,255.255.255.0,24h
EOF

echo "Enabling and starting hostapd and dnsmasq..."
sudo systemctl unmask hostapd
sudo systemctl enable hostapd dnsmasq
sudo systemctl restart hostapd
sudo systemctl restart dnsmasq

echo "Enabling IP forwarding..."
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -w net.ipv4.ip_forward=1

echo "Setting up NAT for outbound internet via eth0..."
# NAT for both wlan0 and eth0 networks going out to upstream (assumed on eth0)
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo netfilter-persistent save

echo "Setup complete."

IP=$(hostname -I | awk '{print $1}')
echo "Access Home Assistant at: http://$IP:8123"

echo "Rebooting..."
sudo reboot
