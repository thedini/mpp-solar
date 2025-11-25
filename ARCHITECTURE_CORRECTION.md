# Architecture Correction: Distributed Sensor System
**Date:** 2025-11-14
**Update:** House sensors are on relaypi, not batterypi

## Corrected System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     MQTT Broker                                  │
│                  192.168.1.134:1883                             │
│              (Running on batterypi)                              │
└─────────────────────────────────────────────────────────────────┘
         ▲                    ▲                    ▲
         │                    │                    │
    house/#              weather/#            battery/#
         │                    │                    │
         │                    │                    │
┌────────┴────────┐  ┌────────┴────────┐  ┌────────┴────────┐
│    relaypi      │  │   batterypi     │  │   batterypi     │
│ house_sensor.py │  │ weather_fetch.py│  │ mpp-solar daemon│
│  (PID unknown)  │  │   (PID 902) ✓   │  │   (PID 856) ✓   │
│                 │  │                 │  │                 │
│ BME280/BME680   │  │ Weather API     │  │ Inverter USB    │
│ I2C sensor      │  │ fetch           │  │ /dev/hidraw0    │
└─────────────────┘  └─────────────────┘  └─────────────────┘

                             │
                             ▼
                    ┌─────────────────┐
                    │   batterypi     │
                    │ web_interface.py│
                    │  (PID 93779)    │
                    │                 │
                    │ Subscribes to:  │
                    │ - house/#       │
                    │ - weather/#     │
                    │ - battery/#     │
                    └─────────────────┘
                             │
                             ▼
                    HTTP :5000
                    Web Dashboard
```

## Key Points

1. **House Sensors (relaypi)**
   - Physical location: Different Raspberry Pi
   - Sensor: BME280 or BME680 (I2C)
   - Publishes: MQTT house/temperature, house/humidity, house/pressure
   - Status: UNKNOWN (needs investigation)

2. **Weather Data (batterypi)**
   - Process: weather_fetcher.py (PID 902)
   - Source: External weather API
   - Publishes: MQTT weather/* topics
   - Status: ✓ WORKING

3. **Inverter Data (batterypi)**
   - Process: mpp-solar daemon (PID 856)
   - Source: USB HID connection to inverter
   - Publishes: MQTT battery/* topics
   - Status: ✓ WORKING

4. **Web Interface (batterypi)**
   - Process: web_interface.py (PID 93779)
   - Subscribes: All MQTT topics
   - Serves: HTTP dashboard on port 5000
   - Status: ⚠️ WORKING but needs fixes

## What This Means for Troubleshooting

### Original Analysis Was Wrong About:
- ❌ "Missing house sensor daemon on batterypi" - INCORRECT
- ✓ House sensor daemon runs on **relaypi**, not batterypi

### Original Analysis Was Correct About:
- ✓ House data is stale (Nov 12 16:15, over 24 hours old)
- ✓ Weather data is current (updating regularly)
- ✓ Web interface logging broken
- ✓ Web interface running as root (should run as constantine)
- ✓ Historical data stale (needs restart to reload)

### New Focus for House Sensor Issue:
Need to check **relaypi**, not batterypi:

```bash
# SSH to relaypi (not batterypi)
ssh relaypi

# Check if house sensor process is running
ps aux | grep -i 'sensor\|bme\|house'

# Check for house sensor scripts
find /home -name '*sensor*.py' -o -name '*bme*.py' -o -name '*house*.py'

# Check systemd services
systemctl list-units --type=service | grep -i 'sensor\|bme\|house'

# Check recent MQTT publishing
# (requires mosquitto_sub with auth)
mosquitto_sub -h 192.168.1.134 -t 'house/#' -v -C 10

# Check logs if service exists
journalctl -u house-sensor -n 50

# Check cron jobs
crontab -l
sudo crontab -l
```

## Web Interface Fixes (Still Valid)

The web interface fixes are still correct and needed:

1. ✓ Fix logging (RotatingFileHandler)
2. ✓ Create systemd service (run as constantine)
3. ✓ Restart to reload historical data
4. ✓ Stop running as root

These fixes are in:
- `web_interface.py` - Updated with proper logging
- `mpp-solar-web.service` - Systemd service file
- `deploy-web-interface.sh` - Automated deployment
- `WEB_INTERFACE_FIX.md` - Complete implementation guide

## Next Steps

### Priority 1: Deploy Web Interface Fixes
```bash
cd /home/constantine/repo/mpp-solar
./deploy-web-interface.sh
```

This will:
- Fix logging
- Stop old root process
- Start systemd service as constantine
- Reload historical data (showing up to Nov 13)

### Priority 2: Investigate relaypi (If House Data Still Stale)
After web interface restart, if house data is STILL stale:

1. SSH to relaypi
2. Check if house sensor process running
3. Check MQTT connectivity from relaypi
4. Check sensor hardware (I2C communication)
5. Review relaypi logs

## Summary of Misunderstanding

**What I Initially Thought:**
> "The house sensor daemon is missing from batterypi. We need to create house_sensor_publisher.py and run it on batterypi."

**Actual Architecture:**
> "The house sensor daemon runs on **relaypi** (different machine) and publishes to MQTT broker on batterypi. The batterypi web_interface.py subscribes to those MQTT topics."

**Why This Matters:**
- Web interface fixes are still valid (logging, systemd, restart)
- House sensor troubleshooting needs to happen on **relaypi**, not batterypi
- The PROJECT_COMPARISON_ANALYSIS.md recommendations about creating a house sensor daemon are not needed for batterypi, but might be useful to check the relaypi implementation

## Files Updated

- ✅ `web_interface.py` - Fixed logging with RotatingFileHandler
- ✅ `mpp-solar-web.service` - Systemd service (run as constantine)
- ✅ `deploy-web-interface.sh` - Automated deployment script
- ✅ `WEB_INTERFACE_FIX.md` - Deployment guide
- ✅ `ARCHITECTURE_CORRECTION.md` - This file (corrected understanding)

## Files That Need Updates

- ⚠️ `TROUBLESHOOTING_HOUSE_PAGE.md` - References "missing daemon on batterypi" (needs correction)
- ⚠️ `PROJECT_COMPARISON_ANALYSIS.md` - Recommends creating house_sensor_publisher.py for batterypi (already exists on relaypi)

**Note:** These analysis files are still valuable for reference and best practices, just the specific recommendation about creating a house sensor daemon on batterypi is not applicable.
