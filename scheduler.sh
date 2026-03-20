#!/bin/bash
# Meeting Scheduler - handles cron-based automated recording
# Run this on the HOST (not in container)

set -e

# Configuration
CONTAINER_NAME="zoombie"
IMAGE_NAME="zoombie"
RECORDINGS_DIR="${ZOOM_RECORDINGS_DIR:-$HOME/zoombieordings}"
API_PORT="${ZOOM_API_PORT:-8080}"
VNC_PORT="${ZOOM_VNC_PORT:-6080}"

# Meeting config (set via env or args)
MEETING_URL="${ZOOM_MEETING_URL:-}"
MEETING_PASSWORD="${ZOOM_PASSWORD:-}"
MEETING_DURATION="${ZOOM_MEETING_DURATION:-3600}"    # expected meeting duration in seconds

# Timing configuration
PREP_BUFFER="${ZOOM_PREP_BUFFER:-60}"                 # system warmup before anything (default: 60s)
JOIN_BUFFER="${ZOOM_JOIN_BUFFER:-300}"                # join meeting this many seconds BEFORE start (default: 5min)
RECORD_OFFSET="${ZOOM_RECORD_OFFSET:-300}"            # start recording offset from meeting start (default: 5min early)
LEAVE_OFFSET="${ZOOM_LEAVE_OFFSET:-0}"                # leave offset from meeting end (positive=early, negative=late, 0=exact)
RECORD_AFTER="${ZOOM_RECORD_AFTER:-600}"              # keep recording after leaving (default: 10min)

usage() {
    cat << EOF
Usage: $(basename $0) [command] [options]

Commands:
    schedule   Schedule a recording via cron
    run        Run recording now (manual trigger)
    start      Start the container
    stop       Stop the container
    status     Show container status
    logs       Show container logs
    cleanup    Remove old containers/images

Environment Variables:
    ZOOM_MEETING_URL       Meeting URL (e.g., https://zoom.us/j/123456789)
    ZOOM_PASSWORD          Meeting passcode
    ZOOM_MEETING_DURATION  Expected meeting duration in seconds (default: 3600)
    
    # Timing (all optional with smart defaults):
    ZOOM_PREP_BUFFER       System warmup before anything (default: 60s)
    ZOOM_JOIN_BUFFER       Join meeting N seconds BEFORE scheduled start (default: 300s = 5min)
    ZOOM_RECORD_OFFSET     Recording start offset from meeting start (default: 300s, can be negative)
    ZOOM_LEAVE_OFFSET      Leave relative to meeting end (default: 0, positive=early, negative=late)
    ZOOM_RECORD_AFTER      Keep recording after leaving (default: 600s = 10min)
    
    ZOOM_RECORDINGS_DIR    Where to save recordings (default: ~/zoombieordings)
    ZOOM_API_PORT          API port (default: 8080)
    ZOOM_VNC_PORT          VNC port (default: 6080)

Timing Model Example (Meeting at 14:00, duration 60min):
    prepBuffer=60, joinBuffer=300, recordOffset=300, leaveOffset=0, recordAfter=600
    -> 13:54: System prep starts (60s warmup)
    -> 13:55: Recording starts (300s offset from 14:00)
    -> 13:55: Join meeting (300s before 14:00)
    -> 14:55: Leave meeting (at scheduled end, offset=0)
    -> 15:05: Stop recording (600s after leaving)

Examples:
    # Run immediately with defaults
    ZOOM_MEETING_URL="https://zoom.us/j/123456789" ZOOM_PASSWORD="abc123" ./scheduler.sh run

    # Custom: join 10min early, record 10min early, leave 5min late, record 15min after
    ZOOM_MEETING_URL="..." ZOOM_JOIN_BUFFER=600 ZOOM_RECORD_OFFSET=600 ZOOM_LEAVE_OFFSET=-300 ZOOM_RECORD_AFTER=900 ./scheduler.sh run

    # Schedule for 2pm daily
    ZOOM_MEETING_URL="..." ./scheduler.sh schedule "0 14 * * 1-5"

    # Schedule for specific meeting time
    ./scheduler.sh schedule-once "2026-03-20 14:00" "https://zoom.us/j/..." "passcode"
EOF
}

# Ensure recordings directory exists
mkdir -p "$RECORDINGS_DIR"

start_container() {
    echo "Starting ZoomPipe recorder container..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "${VNC_PORT}:6080" \
        -p "${API_PORT}:8080" \
        -v "$RECORDINGS_DIR:/recordings" \
        -e DISPLAY=:99 \
        -e ZOOM_MEETING_URL="$MEETING_URL" \
        -e ZOOM_PASSWORD="$MEETING_PASSWORD" \
        -e ZOOM_MEETING_DURATION="$MEETING_DURATION" \
        -e ZOOM_PREP_BUFFER="$PREP_BUFFER" \
        -e ZOOM_JOIN_BUFFER="$JOIN_BUFFER" \
        -e ZOOM_RECORD_OFFSET="$RECORD_OFFSET" \
        -e ZOOM_LEAVE_OFFSET="$LEAVE_OFFSET" \
        -e ZOOM_RECORD_AFTER="$RECORD_AFTER" \
        "$IMAGE_NAME"
    
    echo "Container started. VNC: localhost:${VNC_PORT}, API: localhost:${API_PORT}"
}

stop_container() {
    echo "Stopping ZoomPipe recorder..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
}

run_recording() {
    if [ -z "$MEETING_URL" ]; then
        echo "ERROR: ZOOM_MEETING_URL required"
        exit 1
    fi
    
    echo "Starting recording with:"
    echo "  Meeting: $MEETING_URL"
    echo "  Prep buffer: ${PREP_BUFFER}s"
    echo "  Join buffer: ${JOIN_BUFFER}s (join before start)"
    echo "  Record offset: ${RECORD_OFFSET}s (relative to meeting start)"
    echo "  Duration: ${MEETING_DURATION}s"
    echo "  Leave offset: ${LEAVE_OFFSET}s (relative to end, + early, - late, 0 exact)"
    echo "  Record after: ${RECORD_AFTER}s (keep recording after leaving)"
    echo ""
    
    # Start container if not running
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        start_container
        echo "Waiting for container to initialize..."
        sleep 10
    fi
    
    # Call API to start recording
    curl -s -X POST "http://localhost:${API_PORT}/start-recording" | jq .
    curl -s -X POST "http://localhost:${API_PORT}/join" \
        -H "Content-Type: application/json" \
        -d "{\"meeting_url\": \"$MEETING_URL\", \"password\": \"$MEETING_PASSWORD\"}" | jq .
    
    echo "Recording started. Access VNC at localhost:${VNC_PORT} to verify."
    echo "Recording will run for the configured duration based on timing parameters"
    
    # Run in background - actual timing handled by start-recording.sh inside container
    # We just wait for a reasonable time; the container will stop itself
    sleep $((MEETING_DURATION + RECORD_AFTER + 60))
    
    curl -s -X POST "http://localhost:${API_PORT}/stop-recording" | jq .
    echo "Recording stopped. Check $RECORDINGS_DIR for output."
}

schedule_meeting() {
    local cron_expr="$1"
    if [ -z "$cron_expr" ]; then
        echo "ERROR: Cron expression required"
        exit 1
    fi
    
    # Create cron job that starts recording
    local script_path="$(realpath "$0")"
    local cron_cmd="ZOOM_MEETING_URL='$MEETING_URL' ZOOM_PASSWORD='$MEETING_PASSWORD' ZOOM_MEETING_DURATION='$MEETING_DURATION' $script_path run"
    
    # Remove existing zoombie cron entries
    crontab -l 2>/dev/null | grep -v "zoombie" | crontab -
    
    # Add new cron job (starts 2 min before scheduled time)
    (crontab -l 2>/dev/null; echo "$cron_expr $cron_cmd") | crontab -
    
    echo "Scheduled: $cron_expr"
    echo "Entry: $cron_cmd"
    crontab -l | grep zoombie
}

schedule_once() {
    local start_time="$1"  # "2026-03-20 14:00"
    local meeting_url="$2"
    local password="${3:-}"
    
    # Convert to cron (start early based on MEETING_START_BUFFER)
    local start_date=$(date -d "$start_time" +%Y-%m-%d 2>/dev/null || date -d "@$start_time" +%Y-%m-%d 2>/dev/null)
    local start_hour=$(date -d "$start_time" +%H 2>/dev/null)
    local start_min=$(date -d "$start_time" +%M 2>/dev/null)
    
    # Adjust to start early (default 5 min)
    local early_seconds=$((MEETING_START_BUFFER))
    local early_min=$((start_min - (early_seconds / 60)))
    local early_hour=$start_hour
    
    # Handle minute underflow
    while [ $early_min -lt 0 ]; do
        early_min=$((early_min + 60))
        early_hour=$((early_hour - 1))
    done
    if [ $early_hour -lt 0 ]; then
        early_hour=$((early_hour + 24))
    fi
    
    # Pad with leading zeros
    early_min=$(printf "%02d" $early_min)
    early_hour=$(printf "%02d" $early_hour)
    
    MEETING_URL="$meeting_url"
    MEETING_PASSWORD="$password"
    
    # Use at command for one-time execution
    echo "ZOOM_MEETING_URL='$meeting_url' ZOOM_PASSWORD='$password' $(realpath $0) run" | at "${early_hour}:${early_min} ${start_date}" 2>/dev/null || \
    echo "Scheduling via systemd..."
    
    # Alternative: create systemd timer
    cat > /etc/systemd/system/zoombie.timer << EOF
[Unit]
Description=ZoomPipe Meeting Recorder Timer

[Timer]
OnCalendar=${start_date} ${early_hour}:${early_min}
Persistent=true

[Install]
WantedBy=timers.target
EOF

    cat > /etc/systemd/system/zoombie.service << EOF
[Unit]
Description=ZoomPipe Meeting Recorder
After=network.target

[Service]
Type=oneshot
WorkingDirectory=$(dirname $(realpath "$0"))
Environment="ZOOM_MEETING_URL=$meeting_url"
Environment="ZOOM_PASSWORD=$password"
ExecStart=$(realpath "$0") run
EOF
    
    systemctl daemon-reload
    systemctl enable zoombie.timer
    systemctl start zoombie.timer
    
    echo "Scheduled for $start_time"
    echo "  Starts at: ${early_hour}:${early_min} (${MEETING_START_BUFFER}s early)"
    echo "  Runs for: ${MEETING_DURATION}s + ${MEETING_STOP_BUFFER}s buffer = $((MEETING_DURATION + MEETING_STOP_BUFFER))s total"
}

case "${1:-}" in
    run)    run_recording ;;
    start)  start_container ;;
    stop)   stop_container ;;
    status) docker ps -a | grep "$CONTAINER_NAME" ;;
    logs)   docker logs "$CONTAINER_NAME" ;;
    cleanup)
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
        ;;
    schedule)
        shift
        schedule_meeting "$@"
        ;;
    schedule-once)
        shift
        schedule_once "$@"
        ;;
    *)  usage ;;
esac