## **1. Update System Packages**

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y kodi docker.io docker-compose
sudo usermod -aG cdrom,audio,render,video,plugdev,users,dialout,dip,input $USER
```

## **2. Create Kodi Systemd Service**

Create the service file:

```bash
sudo nano /etc/systemd/system/kodi.service
```


```
[Unit]
Description=Kodi Media Center
After=network.target

[Service]
User=$USER
Group=$USER
Type=simple
ExecStart=/usr/bin/kodi --standalone
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start Kodi:

```bash
sudo systemctl daemon-reload
sudo systemctl enable kodi
sudo systemctl start kodi
```

## **3. Install & Set Up Home Assistant in Docker**

```bash
mkdir -p ~/homeassistant
cd ~/homeassistant
sudo docker run -d   --name homeassistant   --restart=unless-stopped   --privileged   -v ~/homeassistant:/config   --network=host   ghcr.io/home-assistant/home-assistant:stable
```

## **4. Create Home Assistant systemd Service**

Create the service file:

```bash
sudo nano /etc/systemd/system/home-assistant.service
```


```
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
```

Enable the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable home-assistant
sudo systemctl start home-assistant
```

## **5. Enable Docker to Start on Boot**

```bash
sudo systemctl enable docker
```

## **6. Reboot & Verify**

```bash
sudo reboot
```

After reboot:

- **Kodi should launch automatically.**  
- **Home Assistant should start in Docker.**  
- **Check Home Assistant status:**

```bash
sudo systemctl status home-assistant
```

- **Access Home Assistant at:** `http://<Pi-IP>:8123`

---

## **7. Set Up Local Network: DHCP, WiFi AP & Ethernet LAN**

### 7.1 Install required packages

```bash
sudo apt install -y hostapd dnsmasq
sudo systemctl stop hostapd
sudo systemctl stop dnsmasq
```

### 7.2 Configure static IP for Ethernet (LAN port)

Edit dhcpcd config:

```bash
sudo nano /etc/dhcpcd.conf
```

Add at the end:

```
interface eth0
static ip_address=192.168.50.1/24
nohook wpa_supplicant
```

Save and exit.

Restart dhcpcd:

```bash
sudo systemctl restart dhcpcd
```

### 7.3 Configure DHCP server (dnsmasq)

Backup default config:

```bash
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
```

Create new config file:

```bash
sudo nano /etc/dnsmasq.conf
```

Add:

```
interface=eth0
dhcp-range=192.168.50.2,192.168.50.100,255.255.255.0,24h
```

Save and exit.

### 7.4 Configure WiFi Access Point (hostapd)

Create hostapd config:

```bash
sudo nano /etc/hostapd/hostapd.conf
```

Example config (change SSID and password):

```
interface=wlan0
driver=nl80211
ssid=PiAP
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=YourStrongPassword
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
```

Link config in defaults file:

```bash
sudo nano /etc/default/hostapd
```

Set:

```
DAEMON_CONF="/etc/hostapd/hostapd.conf"
```

### 7.5 Enable IP forwarding (optional for internet sharing)

Edit sysctl:

```bash
sudo nano /etc/sysctl.conf
```

Uncomment:

```
net.ipv4.ip_forward=1
```

Apply immediately:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

### 7.6 (Optional) Setup NAT for internet sharing

```bash
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo sh -c "iptables-save > /etc/iptables.ipv4.nat"
```

Edit `/etc/rc.local`:

```bash
sudo nano /etc/rc.local
```

Add above `exit 0`:

```
iptables-restore < /etc/iptables.ipv4.nat
```

### 7.7 Enable and start services

```bash
sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl restart hostapd
sudo systemctl restart dnsmasq
sudo systemctl restart dhcpcd
```

### 7.8 Connect your Waveshare relay to Ethernet port

It should receive an IP between `192.168.50.2` and `192.168.50.100`.

---

You’re all set! Your Pi now provides:

- Ethernet LAN with static IP and DHCP  
- WiFi Access Point with your chosen SSID and password  

Let me know if you want help adding internet sharing or firewall rules.
