#!/bin/bash
# Start recording with environment-based meeting config
# Called by scheduler.sh or directly

set -e

MEETING_URL="${ZOOM_MEETING_URL:-}"
MEETING_PASSWORD="${ZOOM_PASSWORD:-}"
DURATION="${ZOOM_MEETING_DURATION:-3600}"  # default 1 hour
RECORDING_DIR="/recordings"
DISPLAY=:99

# Generate output filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${RECORDING_DIR}/meeting_${TIMESTAMP}.mp4"

echo "=== Zoom Recorder Starting ==="
echo "Time: $(date)"
echo "Meeting: ${MEETING_URL:-manual}"
echo "Output: ${OUTPUT_FILE}"
echo ""

# Start ffmpeg recording
echo "Starting ffmpeg recording..."
ffmpeg -f x11grab \
    -framerate 30 \
    -video_size 1920x1080 \
    -i :99 \
    -c:v libx264 \
    -preset fast \
    -crf 23 \
    -pix_fmt yuv420p \
    -t "$DURATION" \
    "$OUTPUT_FILE" &

RECORDER_PID=$!
echo "Recording PID: $RECORDER_PID"

# Launch Zoom with meeting URL if provided
if [ -n "$MEETING_URL" ]; then
    sleep 3
    
    # Zoom client can accept meeting URLs directly
    # For URL with password: zoom.us/j/123456?pwd=xxx
    # Or passcode can be entered manually via VNC
    if command -v zoom &> /dev/null; then
        echo "Launching Zoom: $MEETING_URL"
        nohup zoom "$MEETING_URL" > /tmp/zoom.log 2>&1 &
        ZOOM_PID=$!
        echo "Zoom PID: $ZOOM_PID"
    fi
fi

echo ""
echo "Recording in progress..."
echo "VNC: http://localhost:6080"
echo "API: http://localhost:8080"
echo "Will stop after ${DURATION}s or on SIGINT"
echo ""

# Wait for recording to complete
# Recording stops automatically after DURATION or can be stopped via API
wait $RECORDER_PID

echo ""
echo "=== Recording Complete ==="
echo "File: $OUTPUT_FILE"
ls -lh "$OUTPUT_FILE"