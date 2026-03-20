#!/bin/bash
# Meeting Scheduler - handles cron-based automated recording
# Run this on the HOST (not in container)

set -e

# Configuration
CONTAINER_NAME="zoom-recorder"
IMAGE_NAME="zoom-recorder"
RECORDINGS_DIR="${ZOOM_RECORDINGS_DIR:-$HOME/zoom-recordings}"
API_PORT="${ZOOM_API_PORT:-8080}"
VNC_PORT="${ZOOM_VNC_PORT:-6080}"

# Meeting config (set via env or args)
MEETING_URL="${ZOOM_MEETING_URL:-}"
MEETING_PASSWORD="${ZOOM_PASSWORD:-}"
MEETING_START_BUFFER="${ZOOM_START_BUFFER:-120}"  # seconds to start early
MEETING_DURATION="${ZOOM_MEETING_DURATION:-3600}"   # expected duration

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
    ZOOM_RECORDINGS_DIR    Where to save recordings (default: ~/zoom-recordings)
    ZOOM_API_PORT          API port (default: 8080)
    ZOOM_VNC_PORT          VNC port (default: 6080)

Examples:
    # Run immediately
    ZOOM_MEETING_URL="https://zoom.us/j/123456789" ZOOM_PASSWORD="abc123" ./scheduler.sh run

    # Schedule for 2pm daily
    ZOOM_MEETING_URL="..." ./scheduler.sh schedule "14:00 * * 1-5"

    # Schedule for specific meeting time (starts 2 min early)
    ./scheduler.sh schedule-once "2026-03-20 14:00" "https://zoom.us/j/..." "passcode"
EOF
}

# Ensure recordings directory exists
mkdir -p "$RECORDINGS_DIR"

start_container() {
    echo "Starting Zoom recorder container..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "${VNC_PORT}:6080" \
        -p "${API_PORT}:8080" \
        -v "$RECORDINGS_DIR:/recordings" \
        -e DISPLAY=:99 \
        -e ZOOM_MEETING_URL="$MEETING_URL" \
        -e ZOOM_PASSWORD="$MEETING_PASSWORD" \
        "$IMAGE_NAME"
    
    echo "Container started. VNC: localhost:${VNC_PORT}, API: localhost:${API_PORT}"
}

stop_container() {
    echo "Stopping Zoom recorder..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
}

run_recording() {
    if [ -z "$MEETING_URL" ]; then
        echo "ERROR: ZOOM_MEETING_URL required"
        exit 1
    fi
    
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
    echo "Recording will run for ${MEETING_DURATION}s (or until stopped)"
    
    # Run in background, will auto-stop after duration
    sleep "$MEETING_DURATION"
    
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
    
    # Remove existing zoom-recorder cron entries
    crontab -l 2>/dev/null | grep -v "zoom-recorder" | crontab -
    
    # Add new cron job (starts 2 min before scheduled time)
    (crontab -l 2>/dev/null; echo "$cron_expr $cron_cmd") | crontab -
    
    echo "Scheduled: $cron_expr"
    echo "Entry: $cron_cmd"
    crontab -l | grep zoom-recorder
}

schedule_once() {
    local start_time="$1"  # "2026-03-20 14:00"
    local meeting_url="$2"
    local password="$3"
    
    # Convert to cron (start 2 min early)
    local start_date=$(date -d "$start_time" +%Y-%m-%d 2>/dev/null || date -d "@$start_time" +%Y-%m-%d 2>/dev/null)
    local start_hour=$(date -d "$start_time" +%H 2>/dev/null)
    local start_min=$(date -d "$start_time" +%M 2>/dev/null)
    
    # Adjust to 2 min early
    local early_min=$((start_min - 2))
    local early_hour=$start_hour
    if [ $early_min -lt 0 ]; then
        early_min=$((early_min + 60))
        early_hour=$((early_hour - 1))
    fi
    
    MEETING_URL="$meeting_url"
    MEETING_PASSWORD="$password"
    
    # Use at command for one-time execution
    echo "ZOOM_MEETING_URL='$meeting_url' ZOOM_PASSWORD='$password' $(realpath $0) run" | at "${early_hour}:${early_min} ${start_date}" 2>/dev/null || \
    echo "Scheduling via systemd..."
    
    # Alternative: create systemd timer
    cat > /etc/systemd/system/zoom-recorder.timer << EOF
[Unit]
Description=Zoom Meeting Recorder Timer

[Timer]
OnCalendar=${start_date} ${early_hour}:${early_min}
Persistent=true

[Install]
WantedBy=timers.target
EOF

    cat > /etc/systemd/system/zoom-recorder.service << EOF
[Unit]
Description=Zoom Meeting Recorder
After=network.target

[Service]
Type=oneshot
WorkingDirectory=$(dirname $(realpath "$0"))
Environment="ZOOM_MEETING_URL=$meeting_url"
Environment="ZOOM_PASSWORD=$password"
ExecStart=$(realpath "$0") run
EOF
    
    systemctl daemon-reload
    systemctl enable zoom-recorder.timer
    systemctl start zoom-recorder.timer
    
    echo "Scheduled for $start_time (starting at ${early_hour}:${early_min})"
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