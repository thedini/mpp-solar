# House Page Troubleshooting Session
**Date:** 2025-11-14
**Site:** http://10.241.119.52:5000/house (batterypi)
**Status:** Investigation Complete - Ready for Fixes

## Problem Summary

The house page shows:
- ❌ "Connected" status not displaying
- ❌ Charts not displaying reliably
- ❌ Data is stale (24+ hours old)

## Root Causes Identified

### Issue 1: Missing House Sensor Process (CRITICAL)
**Problem:** No process is reading house sensors and publishing to MQTT

**Evidence:**
- `/api/house` returns stale data: `temperature: 22.22°C @ 2025-11-12T16:15:40` (24+ hours old)
- `/api/weather` returns fresh data: `temperature: 0.3°C @ 2025-11-13T20:51:15` (current)
- Last house Prometheus files: Nov 12 16:15 (`/home/constantine/mpp-solar/prometheus/house-*.prom`)
- No house sensor process found in `ps aux`
- No house sensor systemd service configured

**Working for Comparison:**
- weather_fetcher.py (PID 902) - Running since Nov 1, updating every 10 min ✓

**MQTT Status:**
- `weather/#` topics: Publishing regularly ✓
- `house/#` topics: No messages being published ❌
- web_interface.py IS subscribed to `house/#` (code confirmed)
- MQTT connection active: `192.168.1.134:1883` (confirmed via netstat)

### Issue 2: Stale Historical Data
**Problem:** Web interface only loads historical data on startup

**Evidence:**
- web_interface.py started: Nov 11 at 12:16
- Historical data loaded at startup: Oct 30 - Nov 6 only
- `/api/house_historical` returns 7-day-old data
- New Prometheus files created Nov 7-13 are NOT loaded
- Function: `load_historical_house_weather_data()` at web_interface.py:108

**Fix Required:**
- Restart web_interface.py to reload recent Prometheus files

### Issue 3: Broken Logging
**Problem:** No log output since Nov 11, can't debug issues

**Evidence:**
- `web_interface.log` last modified: Nov 1 at 14:51
- Current process started: Nov 11 at 12:16
- No "Received house data" or MQTT connection messages
- Only old battery errors visible (from Nov 1)

**Impact:**
- Can't see MQTT connection status
- Can't see if house sensor data attempted to arrive
- Can't debug why logging stopped

## System Architecture

### Expected Data Flow
```
House Sensors → [SENSOR SCRIPT] → MQTT (house/#) → web_interface.py
                                                    ├─> house_data{} (memory)
                                                    ├─> house-*.prom files
                                                    └─> /api/house endpoint
```

### Actual Data Flow
```
House Sensors → ❌ NO PROCESS ❌
                └─> Old .prom files exist (Nov 12 16:15)
                └─> Stale data in memory (loaded Nov 11)

Weather → weather_fetcher.py (PID 902) → MQTT → web_interface.py ✓ WORKING
```

## Current Process Status

**Running Processes:**
- ✓ mpp-solar daemon (PID 856, started Nov 1)
- ✓ weather_fetcher.py (PID 902, started Nov 1) - WORKING
- ✓ web_interface.py (PID 93779, started Nov 11) - PARTIALLY WORKING
- ❌ House sensor publisher - NOT FOUND

**File Ownership:**
- Recent house-*.prom files: owned by `root` (last: Nov 12 16:15)
- Recent weather-*.prom files: owned by `root` (last: Nov 13 20:41)

## API Endpoint Status

| Endpoint | Status | Data Age | Notes |
|----------|--------|----------|-------|
| `/api/house` | ✓ 200 | 24+ hrs old | Returns stale data from Nov 12 |
| `/api/weather` | ✓ 200 | Current | Updates every 10 min |
| `/api/house_historical` | ✓ 200 | Oct 30 - Nov 6 | Loaded at startup (Nov 11) |
| `/api/data` | ✓ 200 | Current | Inverter data working |

## Connection Status Logic (house.html)

**How it Works:**
```javascript
// Line 321: let isConnected = false;
// Line 752: async function fetchData()
//   Fetches /api/house + /api/weather
//   If both return .ok → isConnected = true
//   Updates status indicator

// Line 618-624: updateConnectionStatus()
//   Shows "Connected" or "Disconnected" based on isConnected
```

**Current Behavior:**
- Both APIs return HTTP 200 ✓
- APIs return valid JSON ✓
- isConnected logic should work correctly
- "Disconnected" likely due to client detecting stale timestamps

## Chart Issues (house.html)

**Initialization:**
- Line 473-625: `initCharts()` - Creates Chart.js temperature/humidity charts
- Error handling added in latest commit (c1ff88b)

**Data Loading:**
- Line 683-750: `loadHistoricalData()` - Loads from `/api/house_historical`
- Returns: Oct 30 - Nov 6 data (7-day gap to current)
- Line 752-774: `fetchData()` - Polls live data every 30 seconds

**Problem:**
- 7-day gap between historical (Nov 6) and current (Nov 12) data
- Chart.js may not render properly with huge time gaps
- No new historical data being added (house sensor not running)

## Configuration Files

**Daemon Config:** `/home/constantine/mpp-solar/mpp-solar.conf`
```ini
[SETUP]
pause = 60
mqtt_broker = localhost
mqtt_port = 1883

[inverter]
protocol = pi30
port = /dev/hidraw0
outputs = screen,json,prom_file
prom_output_dir = /home/constantine/mpp-solar/prometheus
```

**Web Interface Config:** `/home/constantine/mpp-solar/web.yaml`
```yaml
host: "0.0.0.0"
port: 5000
log_level: "info"
```

**MQTT Broker:** `192.168.1.134:1883`
- web_interface.py connects to this broker (modified from 127.0.0.1)
- Connection confirmed active via netstat

## Codebase Sync Status

**Local & Remote (batterypi):**
- ✓ Both on branch: `test/chart-fixes-combined`
- ✓ Both at commit: `c1ff88b` "Add comprehensive error handling to house page chart initialization"
- ✓ Local: clean working tree
- ✓ Remote: Modified `web_interface.py` (MQTT broker config 127.0.0.1 → 192.168.1.134)

## Next Steps (In Priority Order)

### 1. Find House Sensor Script (CRITICAL)
**Action:** Locate or identify what should be reading house sensors
- Search for sensor reading scripts: `find /home/constantine -name '*sensor*.py'`
- Check systemd services: `systemctl list-units | grep -i sensor`
- Look for BME280/BME680 sensor scripts (common temp/humidity/pressure sensors)
- Check cron jobs: `crontab -l` and `sudo crontab -l`
- Review any README or setup docs for house sensor configuration

### 2. Start House Sensor Process
**Action:** Start the identified house sensor monitoring process
- If systemd service: `sudo systemctl start <service-name>`
- If Python script: `nohup python3 /path/to/sensor_script.py &`
- Verify MQTT messages: `mosquitto_sub -h 192.168.1.134 -t 'house/#' -v`
- Check Prometheus files updating: `watch ls -lt prometheus/house-*.prom`

### 3. Restart Web Interface
**Action:** Restart to reload historical data and fix logging
```bash
ssh batterypi
sudo kill 93779  # Current web_interface.py PID
cd /home/constantine/mpp-solar
nohup python web_interface.py > /dev/null 2>&1 &
# Or: sudo systemctl restart mpp-solar-web (if service exists)
```

**Verify:**
- Check logs: `tail -f web_interface.log`
- Confirm historical data loaded: `curl http://localhost:5000/api/house_historical | jq '.house_temperature[-1]'`
- Should show recent dates (Nov 7-13)

### 4. Verify End-to-End
**Action:** Confirm data flowing correctly
- Access http://10.241.119.52:5000/house
- Check "Connected" status appears
- Verify charts display with no gaps
- Check timestamp updates: `/api/house` should show current time
- Monitor for 5-10 minutes to confirm ongoing updates

### 5. Fix Logging Issue
**Action:** Investigate why logging stopped
- Check logging config in web_interface.py:722
- Verify log file permissions: `ls -la web_interface.log`
- Check disk space: `df -h`
- May need to reconfigure logging or rotate log file

## Investigation Commands Used

**Check running processes:**
```bash
ssh batterypi "ps aux | grep 'web_interface\|weather_fetcher\|mpp-solar'"
```

**Check API responses:**
```bash
curl -s http://10.241.119.52:5000/api/house | jq
curl -s http://10.241.119.52:5000/api/weather | jq
curl -s http://10.241.119.52:5000/api/house_historical | jq keys
```

**Check MQTT connection:**
```bash
ssh batterypi "netstat -an | grep 1883 | grep ESTABLISHED"
```

**Check Prometheus files:**
```bash
ssh batterypi "ls -lt /home/constantine/mpp-solar/prometheus/house-*.prom | head -10"
ssh batterypi "ls -lt /home/constantine/mpp-solar/prometheus/weather-*.prom | head -10"
```

**Check logs:**
```bash
ssh batterypi "tail -100 /home/constantine/mpp-solar/web_interface.log"
ssh batterypi "stat /home/constantine/mpp-solar/web_interface.log"
```

## Key Files to Review

- `/home/constantine/mpp-solar/web_interface.py` - Main Flask app
  - Line 108: `load_historical_house_weather_data()` - Startup historical load
  - Line 523: `on_mqtt_message()` - MQTT message handler
  - Line 544-555: House sensor MQTT handling
  - Line 690: MQTT broker connection string

- `/home/constantine/mpp-solar/templates/house.html` - Frontend
  - Line 321: `isConnected` variable
  - Line 473: `initCharts()` - Chart initialization
  - Line 614: `updateConnectionStatus()` - Connection indicator
  - Line 683: `loadHistoricalData()` - Historical data loading
  - Line 752: `fetchData()` - Live data polling

- `/home/constantine/mpp-solar/weather_fetcher.py` - Working example
  - Reference for how house sensor script should work

## Questions to Resolve

1. **What reads the house sensors?**
   - Is there a BME280/BME680 sensor script?
   - Was it a systemd service or cron job?
   - When did it stop running?

2. **Why did logging stop?**
   - Disk full?
   - Permission issue?
   - Log rotation problem?

3. **Should house sensor script run as root?**
   - Recent .prom files owned by root
   - May need I2C/GPIO permissions

## Contact Points

- **Repository:** /home/constantine/repo/mpp-solar (local)
- **Deployment:** /home/constantine/mpp-solar (batterypi)
- **SSH:** `ssh batterypi`
- **Web Interface:** http://10.241.119.52:5000
- **Branch:** test/chart-fixes-combined
- **Latest Commit:** c1ff88b

---

**Status:** Ready to proceed with fixes. Start with "Find House Sensor Script" as highest priority.
