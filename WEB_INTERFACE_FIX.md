# Web Interface Fix - Implementation Guide
**Date:** 2025-11-14
**Priority:** HIGH - Fix logging, systemd service, restart to reload data

## What Was Fixed

### 1. Logging Configuration (web_interface.py)
**Problem:** Logging stopped working after Nov 11 restart

**Root Cause:** `logging.basicConfig()` without file handler relies on shell redirection, which breaks when process is restarted manually

**Fix Applied:**
```python
# Added RotatingFileHandler with:
- 10MB file size limit
- 5 backup files (50MB total)
- Detailed formatter with function names and line numbers
- Both file and console output
```

**Location:** web_interface.py:721-742

---

### 2. Systemd Service (mpp-solar-web.service)
**Problem:** Web interface running manually as root (PID 93779)

**Issues:**
- No auto-restart on failure
- Security risk (running as root)
- No service management
- Manual startup required after reboot

**Fix Applied:**
```ini
[Service]
Type=simple
User=constantine          # Run as constantine, not root
Group=constantine
Restart=always            # Auto-restart on failure
RestartSec=10

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=...        # Only write to prometheus/ and log file
```

**Location:** mpp-solar-web.service

---

### 3. Deployment Script (deploy-web-interface.sh)
**Problem:** Manual deployment steps error-prone

**Fix Applied:**
Automated script that:
1. Copies files from local → batterypi
2. Stops old manual process (PID 93779)
3. Installs systemd service
4. Fixes permissions
5. Starts service
6. Shows status and logs

**Location:** deploy-web-interface.sh

---

## Deployment Instructions

### Step 1: Review Changes
```bash
cd /home/constantine/repo/mpp-solar

# Review logging changes
git diff web_interface.py

# Review service file
cat mpp-solar-web.service

# Review deployment script
cat deploy-web-interface.sh
```

### Step 2: Make Deployment Script Executable
```bash
chmod +x deploy-web-interface.sh
```

### Step 3: Deploy to batterypi
```bash
# This will:
# - Copy files to batterypi
# - SSH and run installation
# - Kill old process (PID 93779)
# - Install and start systemd service

./deploy-web-interface.sh
```

### Step 4: Verify
```bash
# Check service status
ssh batterypi "sudo systemctl status mpp-solar-web"

# Watch logs in real-time
ssh batterypi "sudo journalctl -u mpp-solar-web -f"

# Test web interface
curl http://10.241.119.52:5000/api/data
curl http://10.241.119.52:5000/api/house
```

### Step 5: Commit Changes
```bash
git add web_interface.py mpp-solar-web.service deploy-web-interface.sh
git commit -m "Fix web interface logging and add systemd service

- Add RotatingFileHandler with 10MB limit and 5 backups
- Create systemd service to run as constantine (not root)
- Add automated deployment script
- Security hardening (NoNewPrivileges, ProtectSystem)
- Auto-restart on failure with 10s delay"

git push origin test/chart-fixes-combined
```

---

## Expected Results

### Before Deployment
```bash
# Old process running as root
$ ssh batterypi "ps aux | grep web_interface"
root  93779  0.1  1.4  562404 57876  python web_interface.py

# No logging since Nov 11
$ ssh batterypi "tail /home/constantine/mpp-solar/web_interface.log"
2025-11-01 14:51:28,121:ERROR:...

# No systemd service
$ ssh batterypi "systemctl status mpp-solar-web"
Unit mpp-solar-web.service could not be found.
```

### After Deployment
```bash
# Service running as constantine
$ ssh batterypi "ps aux | grep web_interface"
constantine  12345  0.1  1.4  562404 57876  python web_interface.py

# Fresh logs
$ ssh batterypi "tail /home/constantine/mpp-solar/web_interface.log"
2025-11-14 19:30:15:INFO:web_interface:main@747: Started data update thread
2025-11-14 19:30:15:INFO:web_interface:main@751: Started MQTT subscriber thread
2025-11-14 19:30:15:INFO:web_interface:start_mqtt_subscriber@708: Connecting to MQTT broker at 192.168.1.134:1883

# Systemd service active
$ ssh batterypi "sudo systemctl status mpp-solar-web"
● mpp-solar-web.service - MPP-Solar Web Interface
   Loaded: loaded (/etc/systemd/system/mpp-solar-web.service; enabled)
   Active: active (running) since Thu 2025-11-14 19:30:15 EST; 2min ago
```

### Historical Data Reload
After restart, web interface will:
- ✓ Reload Prometheus files from disk (up to Nov 13)
- ✓ Show current historical data (not stuck at Nov 6)
- ✓ `/api/house_historical` will include recent data

---

## Service Management Commands

### Start/Stop/Restart
```bash
# Start service
ssh batterypi "sudo systemctl start mpp-solar-web"

# Stop service
ssh batterypi "sudo systemctl stop mpp-solar-web"

# Restart service (reload historical data)
ssh batterypi "sudo systemctl restart mpp-solar-web"

# Check status
ssh batterypi "sudo systemctl status mpp-solar-web"
```

### Logging
```bash
# View recent logs
ssh batterypi "sudo journalctl -u mpp-solar-web -n 50"

# Follow logs in real-time
ssh batterypi "sudo journalctl -u mpp-solar-web -f"

# View file logs
ssh batterypi "tail -f /home/constantine/mpp-solar/web_interface.log"

# View all log files (including rotated)
ssh batterypi "ls -lh /home/constantine/mpp-solar/web_interface.log*"
```

### Enable/Disable Auto-Start
```bash
# Enable auto-start on boot
ssh batterypi "sudo systemctl enable mpp-solar-web"

# Disable auto-start
ssh batterypi "sudo systemctl disable mpp-solar-web"
```

---

## Troubleshooting

### Service Won't Start
```bash
# Check for errors
ssh batterypi "sudo journalctl -u mpp-solar-web -n 100"

# Check if port 5000 is already in use
ssh batterypi "sudo lsof -i :5000"

# Verify Python path
ssh batterypi "ls -la /home/constantine/mpp-solar/venv/bin/python"

# Check file permissions
ssh batterypi "ls -la /home/constantine/mpp-solar/web_interface.py"
```

### Permission Errors
```bash
# Fix ownership
ssh batterypi "sudo chown -R constantine:constantine /home/constantine/mpp-solar/"

# Fix log file permissions
ssh batterypi "sudo chown constantine:constantine /home/constantine/mpp-solar/web_interface.log"

# Fix prometheus directory
ssh batterypi "sudo chown -R constantine:constantine /home/constantine/mpp-solar/prometheus/"
```

### Old Process Still Running
```bash
# Find old process
ssh batterypi "ps aux | grep web_interface"

# Kill it
ssh batterypi "sudo kill <PID>"

# Force kill if needed
ssh batterypi "sudo kill -9 <PID>"
```

---

## Rollback Procedure

If deployment causes issues:

### Step 1: Stop New Service
```bash
ssh batterypi "sudo systemctl stop mpp-solar-web"
ssh batterypi "sudo systemctl disable mpp-solar-web"
```

### Step 2: Restore Old Code
```bash
ssh batterypi "cd /home/constantine/mpp-solar && git checkout HEAD~1 web_interface.py"
```

### Step 3: Start Manually (Old Way)
```bash
ssh batterypi "cd /home/constantine/mpp-solar && nohup sudo venv/bin/python web_interface.py > /dev/null 2>&1 &"
```

---

## Testing Checklist

After deployment, verify:

- [ ] Service is running: `sudo systemctl status mpp-solar-web`
- [ ] Logs are being written: `tail /home/constantine/mpp-solar/web_interface.log`
- [ ] Web interface accessible: `curl http://10.241.119.52:5000/`
- [ ] API endpoints working: `curl http://10.241.119.52:5000/api/data`
- [ ] Historical data updated: `curl http://10.241.119.52:5000/api/house_historical | jq '.house_temperature[-1]'`
- [ ] MQTT connection working: Check logs for "Connected to MQTT broker"
- [ ] House page loads: Visit http://10.241.119.52:5000/house
- [ ] Charts display: Verify no JavaScript errors in browser console
- [ ] Auto-restart works: `sudo systemctl restart mpp-solar-web` and check uptime

---

## Additional Notes

### Why Restart Fixes Historical Data
**Problem:** web_interface.py loads historical data ONCE at startup (line 705)

**Current State:**
- Process started: Nov 11 at 12:16
- Historical data loaded: Oct 30 - Nov 6
- New Prometheus files: Nov 7-13 (not loaded)

**Solution:** Restart process to reload all Prometheus files

**Long-term Fix:** Implement incremental loading (future enhancement)

---

### Security Improvements
The new systemd service includes hardening:

```ini
NoNewPrivileges=true      # Can't gain new privileges
PrivateTmp=true           # Isolated /tmp directory
ProtectSystem=strict      # Read-only system files
ProtectHome=read-only     # Read-only /home (except WritePathspaths)
ReadWritePaths=...        # Only write to specific directories
```

This follows Linux security best practices from systemd documentation.

---

### Log Rotation
The new logging configuration automatically rotates logs:

```
web_interface.log         (current, max 10MB)
web_interface.log.1       (previous)
web_interface.log.2
web_interface.log.3
web_interface.log.4
web_interface.log.5       (oldest)
```

Total: 50MB max (6 files × ~8MB average)

Old logs automatically deleted when rotating past .5

---

## Related Files

- `TROUBLESHOOTING_HOUSE_PAGE.md` - Original investigation (before learning about relaypi)
- `PROJECT_COMPARISON_ANALYSIS.md` - Comparison with GitHub reference projects
- `web_interface.py` - Main Flask application
- `mpp-solar-web.service` - Systemd service file
- `deploy-web-interface.sh` - Automated deployment script

---

**Status:** Ready to deploy. Run `./deploy-web-interface.sh` to apply fixes.
