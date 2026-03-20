#!/bin/bash
# Start recording with environment-based meeting config
# Called by scheduler.sh or directly

set -e

MEETING_URL="${ZOOM_MEETING_URL:-}"
MEETING_PASSWORD="${ZOOM_PASSWORD:-}"
DURATION="${ZOOM_MEETING_DURATION:-3600}"        # Meeting duration in seconds
START_BUFFER="${ZOOM_START_BUFFER:-300}"          # Seconds to start early
STOP_BUFFER="${ZOOM_STOP_BUFFER:-600}"            # Seconds to record after meeting ends
LEAVE_EARLY="${ZOOM_LEAVE_EARLY:-0}"              # Optional: leave X seconds before duration
RECORDING_DIR="/recordings"
DISPLAY=:99

# Calculate timing
TOTAL_RUNTIME=$((DURATION + STOP_BUFFER))
MEETING_START_TIME=$(date +%s)
MEETING_END_TIME=$((MEETING_START_TIME + DURATION))
FULL_END_TIME=$((MEETING_START_TIME + TOTAL_RUNTIME))

# Generate output filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${RECORDING_DIR}/meeting_${TIMESTAMP}.mp4"

echo "=== Zoom Recorder Starting ==="
echo "Time: $(date)"
echo "Meeting: ${MEETING_URL:-manual}"
echo "Output: $OUTPUT_FILE"
echo ""
echo "Timing configuration:"
echo "  Start early: ${START_BUFFER}s"
echo "  Meeting duration: ${DURATION}s"
echo "  Leave meeting at: $(date -d @${MEETING_END_TIME} '+%H:%M:%S')"
echo "  Record extra: ${STOP_BUFFER}s"
echo "  Total runtime: ${TOTAL_RUNTIME}s"
echo ""

# Start ffmpeg recording (runs for full total runtime)
echo "Starting ffmpeg recording (will run for ${TOTAL_RUNTIME}s)..."
ffmpeg -f x11grab \
    -framerate 30 \
    -video_size 1920x1080 \
    -i :99 \
    -c:v libx264 \
    -preset fast \
    -crf 23 \
    -pix_fmt yuv420p \
    -t "$TOTAL_RUNTIME" \
    "$OUTPUT_FILE" &

RECORDER_PID=$!
echo "Recording PID: $RECORDER_PID"

# Launch Zoom with meeting URL if provided
if [ -n "$MEETING_URL" ]; then
    sleep 3
    
    if command -v zoom &> /dev/null; then
        echo "Launching Zoom: $MEETING_URL"
        nohup zoom "$MEETING_URL" > /tmp/zoom.log 2>&1 &
        ZOOM_PID=$!
        echo "Zoom PID: $ZOOM_PID"
        
        # Calculate when to leave the meeting
        # By default, leave exactly at DURATION (meeting end time)
        # Optionally leave early (LEAVE_EARLY) for buffer before scheduled end
        LEAVE_AT=$((DURATION - LEAVE_EARLY))
        echo "Will leave meeting in ${LEAVE_AT}s..."
        
        # Wait until it's time to leave, then close Zoom
        sleep "$LEAVE_AT"
        
        if kill -0 $ZOOM_PID 2>/dev/null; then
            echo "Leaving meeting (closing Zoom)..."
            kill $ZOOM_PID 2>/dev/null || true
        fi
    fi
fi

echo ""
echo "Zoom has left the meeting."
echo "Continuing to record for ${STOP_BUFFER}s (capturing post-meeting)..."
echo ""

# Wait for remaining recording time (if any)
REMAINING=$((TOTAL_RUNTIME - DURATION))
if [ $REMAINING -gt 0 ]; then
    sleep $REMAINING
fi

# Ensure recorder is stopped
if kill -0 $RECORDER_PID 2>/dev/null; then
    echo "Stopping recorder..."
    kill $RECORDER_PID 2>/dev/null || true
    wait $RECORDER_PID 2>/dev/null || true
fi

echo ""
echo "=== Recording Complete ==="
echo "File: $OUTPUT_FILE"
ls -lh "$OUTPUT_FILE"