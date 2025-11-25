#!/bin/bash
# Deploy Web Interface Fixes
# This script:
# 1. Copies updated web_interface.py to batterypi
# 2. Installs systemd service
# 3. Stops old manual process
# 4. Starts new systemd service

set -e

echo "=== MPP-Solar Web Interface Deployment ==="
echo ""

# Check if we're on the right machine
if [ "$HOSTNAME" != "batterypi" ]; then
    echo "Running deployment from $(hostname) to batterypi..."

    # Copy files to batterypi
    echo "1. Copying updated files to batterypi..."
    scp web_interface.py batterypi:/home/constantine/mpp-solar/
    scp mpp-solar-web.service batterypi:/tmp/

    # Run the rest on batterypi
    echo "2. Connecting to batterypi to complete deployment..."
    ssh batterypi "cd /home/constantine/mpp-solar && bash deploy-web-interface.sh"

    echo ""
    echo "✓ Deployment complete!"
    echo "Check status: ssh batterypi 'sudo systemctl status mpp-solar-web'"
    exit 0
fi

# We're on batterypi - do the actual deployment
echo "Running on batterypi - deploying..."

# 1. Install systemd service
echo "1. Installing systemd service..."
sudo cp /tmp/mpp-solar-web.service /etc/systemd/system/
sudo systemctl daemon-reload

# 2. Stop old manual process (if running)
echo "2. Stopping old web_interface process..."
OLD_PID=$(pgrep -f "python.*web_interface.py" || echo "")
if [ -n "$OLD_PID" ]; then
    echo "   Found old process: PID $OLD_PID"
    sudo kill $OLD_PID || true
    sleep 2

    # Force kill if still running
    if ps -p $OLD_PID > /dev/null 2>&1; then
        echo "   Force killing PID $OLD_PID"
        sudo kill -9 $OLD_PID || true
    fi
    echo "   ✓ Old process stopped"
else
    echo "   No old process found"
fi

# 3. Backup old log (for reference)
echo "3. Rotating old log file..."
if [ -f /home/constantine/mpp-solar/web_interface.log ]; then
    sudo mv /home/constantine/mpp-solar/web_interface.log \
            /home/constantine/mpp-solar/web_interface.log.old
    echo "   ✓ Old log saved as web_interface.log.old"
fi

# 4. Fix permissions
echo "4. Fixing permissions..."
sudo chown constantine:constantine /home/constantine/mpp-solar/web_interface.py
sudo chown -R constantine:constantine /home/constantine/mpp-solar/prometheus
sudo touch /home/constantine/mpp-solar/web_interface.log
sudo chown constantine:constantine /home/constantine/mpp-solar/web_interface.log

# 5. Enable and start service
echo "5. Starting mpp-solar-web service..."
sudo systemctl enable mpp-solar-web
sudo systemctl start mpp-solar-web

# 6. Wait a moment for startup
echo "6. Waiting for service to start..."
sleep 3

# 7. Check status
echo ""
echo "=== Service Status ==="
sudo systemctl status mpp-solar-web --no-pager || true

echo ""
echo "=== Recent Logs ==="
sudo journalctl -u mpp-solar-web -n 20 --no-pager

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Useful commands:"
echo "  - Check status:  sudo systemctl status mpp-solar-web"
echo "  - View logs:     sudo journalctl -u mpp-solar-web -f"
echo "  - Restart:       sudo systemctl restart mpp-solar-web"
echo "  - Stop:          sudo systemctl stop mpp-solar-web"
echo ""
echo "Web interface should be accessible at: http://10.241.119.52:5000"
