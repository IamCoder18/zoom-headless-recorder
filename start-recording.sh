#!/bin/bash
# Start recording with environment-based meeting config
# Called by scheduler.sh or directly
#
# Timing model:
#   prepBuffer    - System warmup time (Xvfb, ZoomPipe ready) before we start anything
#   joinBuffer    - Join meeting X seconds BEFORE scheduled start
#   recordOffset  - When to START recording relative to meeting start (can be negative)
#   leaveOffset   - When to LEAVE relative to meeting end (positive=early, negative=late, 0=exact)
#   recordAfter   - How long to KEEP RECORDING after we leave
#
# Example: Meeting at 14:00, duration 60min
#   prepBuffer=60, joinBuffer=300, recordOffset=300, leaveOffset=0, recordAfter=600
#   -> 13:55: Start prep (ensure system ready)
#   -> 13:55: Start recording (recordOffset from 14:00 = 14:00-300s = 13:55)
#   -> 13:55: Join meeting (joinBuffer from 14:00 = 13:55)
#   -> 14:55: Leave meeting (14:00 + 60min + 0 = 14:55)
#   -> 15:05: Stop recording (14:55 + 600s)

set -e

MEETING_URL="${ZOOM_MEETING_URL:-}"
MEETING_PASSWORD="${ZOOM_PASSWORD:-}"
DURATION="${ZOOM_MEETING_DURATION:-3600}"           # Expected meeting duration in seconds

# Timing configuration
PREP_BUFFER="${ZOOM_PREP_BUFFER:-60}"                # System warmup before anything (default: 60s)
JOIN_BUFFER="${ZOOM_JOIN_BUFFER:-300}"               # Join meeting this many seconds BEFORE start (default: 300s = 5min)
RECORD_OFFSET="${ZOOM_RECORD_OFFSET:-300}"            # Start recording offset from meeting start (positive=early, negative=after)
LEAVE_OFFSET="${ZOOM_LEAVE_OFFSET:-0}"                # Leave meeting offset from end (positive=early, negative=late, 0=exact)
RECORD_AFTER="${ZOOM_RECORD_AFTER:-600}"              # Keep recording after leaving (default: 600s = 10min)

RECORDING_DIR="/recordings"
DISPLAY=:99

# Current time and meeting schedule
NOW=$(date +%s)
SCHEDULED_START=$NOW                                 # Meeting scheduled to start now (for immediate run)
SCHEDULED_END=$((SCHEDULED_START + DURATION))

# Calculate when to start each phase
# Phase 1: System prep starts at (scheduled start - joinBuffer - prepBuffer)
# Phase 2: Recording starts at (scheduled start + recordOffset)
# Phase 3: Join meeting at (scheduled start - joinBuffer)
# Phase 4: Leave meeting at (scheduled end + leaveOffset)
# Phase 5: Stop recording at (leave time + recordAfter)

RECORD_START_TIME=$((SCHEDULED_START + RECORD_OFFSET))
JOIN_TIME=$((SCHEDULED_START - JOIN_BUFFER))
LEAVE_TIME=$((SCHEDULED_END + LEAVE_OFFSET))
RECORD_END_TIME=$((LEAVE_TIME + RECORD_AFTER))

# Total runtime from NOW
TOTAL_RUNTIME=$((RECORD_END_TIME - NOW))

# Generate output filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${RECORDING_DIR}/meeting_${TIMESTAMP}.mp4"

echo "=== ZoomPipePipe Starting ==="
echo "Time: $(date)"
echo "Meeting: ${MEETING_URL:-manual}"
echo "Output: $OUTPUT_FILE"
echo ""
echo "Timing configuration:"
echo "  Prep buffer: ${PREP_BUFFER}s (system warmup)"
echo "  Join buffer: ${JOIN_BUFFER}s (join before scheduled start)"
echo "  Record offset: ${RECORD_OFFSET}s (relative to meeting start)"
echo "  Leave offset: ${LEAVE_OFFSET}s (relative to meeting end, + = early, - = late)"
echo "  Record after: ${RECORD_AFTER}s (keep recording after leaving)"
echo ""
echo "Schedule (relative to now):"
echo "  Recording starts: +$((RECORD_START_TIME - NOW))s"
echo "  Join meeting: +$((JOIN_TIME - NOW))s"
echo "  Leave meeting: +$((LEAVE_TIME - NOW))s"
echo "  Stop recording: +$((RECORD_END_TIME - NOW))s"
echo "  Total runtime: ${TOTAL_RUNTIME}s"
echo ""

# Wait for prep buffer (system warmup)
if [ $PREP_BUFFER -gt 0 ]; then
    echo "Warming up system (${PREP_BUFFER}s)..."
    sleep $PREP_BUFFER
fi

# Start ffmpeg recording (runs from record start time to end time)
echo "Starting ffmpeg recording (will run for ${TOTAL_RUNTIME}s from start)..."
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

# Launch ZoomPipe with meeting URL if provided
if [ -n "$MEETING_URL" ]; then
    # Wait until it's time to join
    SECONDS_TO_JOIN=$((JOIN_TIME - NOW - PREP_BUFFER))
    if [ $SECONDS_TO_JOIN -gt 0 ]; then
        echo "Waiting to join meeting in ${SECONDS_TO_JOIN}s..."
        sleep $SECONDS_TO_JOIN
    fi
    
    if command -v zoom &> /dev/null; then
        echo "Launching ZoomPipe and joining meeting: $MEETING_URL"
        nohup zoom "$MEETING_URL" > /tmp/zoom.log 2>&1 &
        ZOOM_PID=$!
        echo "ZoomPipe PID: $ZOOM_PID"
        
        # Wait until it's time to leave
        SECONDS_TO_LEAVE=$((LEAVE_TIME - JOIN_TIME))
        if [ $SECONDS_TO_LEAVE -gt 0 ]; then
            echo "Will leave meeting in ${SECONDS_TO_LEAVE}s..."
            sleep $SECONDS_TO_LEAVE
        fi
        
        # Leave the meeting
        if kill -0 $ZOOM_PID 2>/dev/null; then
            echo "Leaving meeting (closing ZoomPipe)..."
            kill $ZOOM_PID 2>/dev/null || true
        fi
    fi
fi

echo ""
echo "ZoomPipe has left the meeting."
echo "Continuing to record for ${RECORD_AFTER}s (capturing post-meeting)..."
echo ""

# Wait for remaining recording time
REMAINING=$((RECORD_END_TIME - LEAVE_TIME))
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