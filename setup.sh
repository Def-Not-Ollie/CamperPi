#!/bin/bash
set -e

USER=$(whoami)
HA_CONFIG_DIR="/home/$USER/homeassistant"

echo "Starting CamperPi setup as $USER..."

echo "Unblocking Wi-Fi..."
sudo rfkill unblock wifi > /dev/null 2>&1

echo "Syncing time..."
sudo timedatectl set-ntp on > /dev/null 2>&1
sudo systemctl restart systemd-timesyncd > /dev/null 2>&1

echo "Preconfiguring iptables-persistent..."
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections > /dev/null 2>&1
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections > /dev/null 2>&1

echo "Installing packages..."
sudo apt update -qq > /dev/null 2>&1
sudo apt full-upgrade -y -qq > /dev/null 2>&1
sudo apt install -y -qq kodi docker.io docker-compose hostapd dnsmasq iptables-persistent netfilter-persistent > /dev/null 2>&1

echo "Enabling Docker..."
sudo systemctl enable docker > /dev/null 2>&1
sudo systemctl start docker > /dev/null 2>&1

echo "Setting up Home Assistant..."
mkdir -p "$HA_CONFIG_DIR"
if sudo docker ps -a --format '{{.Names}}' | grep -q '^homeassistant$'; then
    echo "Home Assistant container exists. Skipping creation."
else
    echo "Creating Home Assistant container (starts on reboot)..."
    sudo docker create --name homeassistant --restart=unless-stopped --privileged -v "$HA_CONFIG_DIR:/config" --network=host ghcr.io/home-assistant/home-assistant:stable > /dev/null 2>&1
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

sudo systemctl daemon-reload > /dev/null 2>&1
sudo systemctl enable home-assistant > /dev/null 2>&1

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

sudo systemctl daemon-reload > /dev/null 2>&1
sudo systemctl enable kodi > /dev/null 2>&1

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

sudo sed -i '/^DAEMON_CONF=/d' /etc/default/hostapd
echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' | sudo tee -a /etc/default/hostapd > /dev/null 2>&1

echo "Configuring static IP for wlan0..."
echo -e "\ninterface wlan0\n    static ip_address=192.168.50.1/24\n    nohook wpa_supplicant" | sudo tee -a /etc/dhcpcd.conf > /dev/null 2>&1

echo "Configuring dnsmasq..."
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig 2>/dev/null || true
sudo tee /etc/dnsmasq.conf > /dev/null <<EOF
interface=wlan0
dhcp-range=192.168.50.2,192.168.50.20,255.255.255.0,24h
EOF

sudo systemctl unmask hostapd > /dev/null 2>&1
sudo systemctl enable hostapd > /dev/null 2>&1
sudo systemctl enable dnsmasq > /dev/null 2>&1
sudo systemctl restart hostapd > /dev/null 2>&1
sudo systemctl restart dnsmasq > /dev/null 2>&1

sudo systemctl is-active hostapd > /dev/null && echo "hostapd is running" || echo "hostapd NOT running"
sudo systemctl is-active dnsmasq > /dev/null && echo "dnsmasq is running" || echo "dnsmasq NOT running"

ip addr show wlan0 | grep 'inet ' | awk '{print "Hotspot IP: "$2}'

echo "Setting up NAT (eth0 → wlan0)..."
sudo iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE > /dev/null 2>&1
sudo netfilter-persistent save > /dev/null 2>&1

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
