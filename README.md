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

Paste the following (replace `admin` with your username or keep `$USER`):

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
sudo docker run -d \
  --name homeassistant \
  --restart=unless-stopped \
  --privileged \
  -v ~/homeassistant:/config \
  --network=host \
  ghcr.io/home-assistant/home-assistant:stable
```

## **4. Create Home Assistant systemd Service**

Create the service file:

```bash
sudo nano /etc/systemd/system/home-assistant.service
```

Paste the following (replace `admin` with your username or keep `$USER`):

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
