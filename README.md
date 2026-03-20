# zoom-headless-recorder

A reliable Docker-based solution for automated Zoom meeting joining and recording with scheduler and API.

## Quick Start

```bash
# 1. Build the image
docker build -t zoom-recorder .

# 2. Run a meeting immediately
ZOOM_MEETING_URL="https://zoom.us/j/123456789" \
ZOOM_PASSWORD="abc123" \
./scheduler.sh run
```

## Architecture

- **Docker container** with Xvfb, Zoom client, ffmpeg, noVNC
- **Scheduler** (cron/systemd) for automated runs
- **REST API** for recording control
- **Environment-based config** for meeting credentials

## Meeting Parameters

Passed via environment variables:

| Variable | Description | Required |
|----------|-------------|----------|
| `ZOOM_MEETING_URL` | Full meeting URL (e.g., `https://zoom.us/j/123456789`) | Yes |
| `ZOOM_PASSWORD` | Meeting passcode | If meeting requires it |
| `ZOOM_MEETING_DURATION` | Recording duration in seconds (default: 3600) | No |
| `ZOOM_RECORDINGS_DIR` | Host path for recordings (default: `~/zoom-recordings`) | No |

## Usage

### Manual Run

```bash
# Full manual with custom duration and output dir
ZOOM_MEETING_URL="https://zoom.us/j/123456789" \
ZOOM_PASSWORD="secret" \
ZOOM_MEETING_DURATION=7200 \
ZOOM_RECORDINGS_DIR=/my/recordings \
./scheduler.sh run
```

### Scheduled (Cron)

```bash
# Schedule daily at 2pm (Mon-Fri)
ZOOM_MEETING_URL="https://zoom.us/j/..." \
ZOOM_PASSWORD="..." \
./scheduler.sh schedule "0 14 * * 1-5"
```

### One-Time Schedule

```bash
# Schedule for specific date/time (starts 2 min early)
./scheduler.sh schedule-once "2026-03-25 14:00" "https://zoom.us/j/..." "password"
```

This creates systemd timers (Linux) - works reliably without running container 24/7.

### Start/Stop Container Manually

```bash
./scheduler.sh start    # Start container, keep running
./scheduler.sh stop     # Stop container
./scheduler.sh status   # Check if running
./scheduler.sh logs     # View container logs
```

### API Control

When container is running:

```bash
# Start recording
curl -X POST http://localhost:8080/start-recording

# Join meeting
curl -X POST http://localhost:8080/join \
  -H "Content-Type: application/json" \
  -d '{"meeting_url": "https://zoom.us/j/...", "password": "..."}'

# Stop recording
curl -X POST http://localhost:8080/stop-recording

# Check status
curl http://localhost:8080/status

# List recordings
curl http://localhost:8080/recordings
```

## Access

- **noVNC**: http://localhost:6080 (browser-based virtual desktop)
- **API**: http://localhost:8080
- **VNC**: localhost:5900 (raw VNC if needed)

## Recording Output

Recordings saved to mounted directory:
- `meeting_YYYYMMDD_HHMMSS.mp4` - Full meeting recording

## Container Lifecycle

The scheduler manages container lifecycle intelligently:

1. **Starts ~2 minutes before meeting** (configurable via `ZOOM_START_BUFFER`)
2. **Runs for meeting duration** (or `ZOOM_MEETING_DURATION`)
3. **Auto-stops after recording completes**
4. **No persistent container** - saves resources

Using `scheduler.sh schedule-once` with systemd timers ensures:
- Container only runs when needed
- Starts early enough to initialize (2 min buffer)
- Stops automatically after duration

## Legal Note

⚠️ Only use on meetings you host or have explicit permission to record. Automated recording may violate Zoom Terms of Service.

## License

MIT