## Quick Installation

```bash
chmod +x deploy/setup.sh
sudo deploy/setup.sh
```

## Manual Installation

1. Create installation directory:

```bash
sudo mkdir -p /opt/sacha.house
sudo chown sacha:sacha /opt/sacha.house
```

2. Copy initial binary to `/opt/sacha.house/sacha.house` and set ownership:

```bash
sudo chown sacha:sacha /opt/sacha.house/sacha.house
```

3. Install systemd service:

```bash
sudo cp deploy/sacha.house.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable sacha.house.service
sudo systemctl start sacha.house.service
```

4. Setup auto-update:

```bash
sudo cp deploy/update.sh /opt/sacha.house/
sudo chmod +x /opt/sacha.house/update.sh
```

5. Optionally edit `/opt/sacha.house/update.sh` to change `EMAIL_TO` if needed (defaults to "admin")

6. Install crontab for automatic updates:

```bash
sudo crontab -e
```

Add the line from `deploy/crontab`:

```
0 0 * * * /opt/sacha.house/update.sh >> /var/log/sacha.house-update.log 2>&1
```

7. Create log file:

```bash
sudo touch /var/log/sacha.house-update.log
sudo chmod 644 /var/log/sacha.house-update.log
```

## Manual Update

```bash
sudo /opt/sacha.house/update.sh
```

## Check Status

```bash
sudo systemctl status sacha.house.service
sudo journalctl -u sacha.house.service -f
```
