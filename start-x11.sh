#!/bin/bash
# Start Xvfb virtual display and noVNC for browser-based control

echo "Starting Xvfb display :99..."
Xvfb :99 -screen 0 1920x1080x24 &

# Wait for Xvfb to start
sleep 2

echo "Starting X11 VNC server..."
x11vnc -display :99 -forever -shared -bg -nopw

echo "Starting noVNC websockify..."
cd /usr/share/novnc/utils
python3 ./websockify --web /var/www/html 6080 localhost:5900 &

echo "Starting window manager (fluxbox)..."
fluxbox -display :99 &
sleep 1

echo ""
echo "========================================"
echo "Zoom Recorder ready!"
echo "Access at: http://localhost:6080"
echo "VNC password: (none)"
echo ""
echo "To record: Run the recording script in the container"
echo "========================================"

# Keep container running
tail -f /dev/null