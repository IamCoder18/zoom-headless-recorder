#!/bin/bash
# Automated Zoom meeting join and recording script

set -e

# Configuration
MEETING_URL="${ZOOM_MEETING_URL:-}"
MEETING_PASSWORD="${ZOOM_PASSWORD:-}"
RECORDING_DIR="/recordings"
DISPLAY=:99

# Generate output filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${RECORDING_DIR}/meeting_${TIMESTAMP}.mp4"

echo "=== Zoom Meeting Recorder ==="
echo "Meeting: ${MEETING_URL:-NOT SET}"
echo "Output: ${OUTPUT_FILE}"
echo ""

# Check if meeting URL is provided
if [ -z "$MEETING_URL" ]; then
    echo "ERROR: ZOOM_MEETING_URL not set"
    echo "Usage: docker run -e ZOOM_MEETING_URL='https://zoom.us/j/...' -e ZOOM_PASSWORD='...' ..."
    exit 1
fi

# Start ffmpeg recording in background
echo "Starting screen recording..."
ffmpeg -f x11grab \
    -framerate 30 \
    -video_size 1920x1080 \
    -i :99 \
    -c:v libx264 \
    -preset fast \
    -crf 23 \
    -pix_fmt yuv420p \
    "$OUTPUT_FILE" &

RECORDER_PID=$!
echo "Recording started (PID: $RECORDER_PID)"

# Give ffmpeg time to initialize
sleep 3

# Try to open Zoom (requires Zoom to be installed in container)
# This is a placeholder - actual Zoom launch depends on having the .deb
if command -v zoom &> /dev/null; then
    echo "Launching Zoom..."
    # Zoom would be launched here with meeting URL
    # zoom "$MEETING_URL"
    echo "Note: Zoom must be installed in the container"
else
    echo "Note: Zoom not installed - use noVNC to manually join"
fi

echo ""
echo "Recording in progress..."
echo "Access noVNC at http://localhost:6080 to control the meeting"
echo "Press Ctrl+C to stop recording"
echo ""

# Wait for user interrupt or signal
wait $RECORDER_PID