## **1. Update & Install Required Packages**

```bash
sudo apt update  
sudo apt upgrade -y  
sudo apt install -y kodi docker.io docker-compose  
```

## **2. Set Up Kodi to Start on Boot**

```bash
sudo nano /etc/systemd/system/kodi.service  
```

```
[Unit]  
Description=Kodi Media Center  
After=network.target  

[Service]  
User=admin  
Group=admin  
Type=simple  
ExecStart=/usr/bin/kodi --standalone  
Restart=always  
RestartSec=5  

[Install]  
WantedBy=multi-user.target  

```

```bash
sudo systemctl enable kodi
sudo systemctl start kodi 
```

## **3. Install & Set Up Home Assistant in Docker**

```bash
mkdir -p ~/homeassistant  
cd ~/homeassistant  

```

```bash
sudo docker run -d \  
  --name homeassistant \  
  --restart=unless-stopped \  
  --privileged \  
  -v ~/homeassistant:/config \  
  --network=host \  
  ghcr.io/home-assistant/home-assistant:stable  
```

## **4. Set Up Home Assistant to Start on Boot**

```bash
sudo nano /etc/systemd/system/home-assistant.service  
```

```
[Unit]  
Description=Home Assistant  
After=network.target docker.service  
Requires=docker.service  

[Service]  
User=admin  
Group=admin  
ExecStart=/usr/bin/docker start homeassistant  
ExecStop=/usr/bin/docker stop homeassistant  
Restart=always  
RestartSec=5  

[Install]  
WantedBy=multi-user.target  

```

```bash
sudo systemctl enable home-assistant  
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

- **Access Home Assistant at:**`http://<Pi-IP>:8123`
