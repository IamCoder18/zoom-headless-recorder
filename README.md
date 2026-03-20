# zoom-headless-recorder

A reliable, containerized solution for automated Zoom meeting joining and recording.

## Architecture

- **Docker container** with:
  - Xvfb (virtual framebuffer for headless display)
  - Zoom client (via wine or native Linux)
  - ffmpeg for screen recording
  - noVNC for browser-based control
- **Automation scripts** to join meetings and control recording
- **REST API** (optional) for programmatic control

## Quick Start

```bash
# Build the container
docker build -t zoom-recorder .

# Run with recording
docker run -d \
  -v $(pwd)/recordings:/recordings \
  -p 6080:6080 \
  zoom-recorder

# Join a meeting (via noVNC browser at http://localhost:6080)
# Or use the API (see below)
```

## Requirements

- Docker
- Linux host (recommended for best X11 compatibility)
- 2GB+ RAM allocated to container
- Meeting host permission (or your own meetings)

## Usage

### Method 1: Browser Control (noVNC)
1. Open `http://localhost:6080` in browser
2. Use the virtual desktop to:
   - Launch Zoom client
   - Join your meeting
   - Start recording via included ffmpeg command

### Method 2: Automated Join
```bash
# Set meeting details
export ZOOM_MEETING_URL="https://zoom.us/j/123456789"
export ZOOM_PASSWORD="password"

# Run the automation
docker run -d \
  -e ZOOM_MEETING_URL="$ZOOM_MEETING_URL" \
  -e ZOOM_PASSWORD="$ZOOM_PASSWORD" \
  -v $(pwd)/recordings:/recordings \
  zoom-recorder ./start-recording.sh
```

### Method 3: API Server
```bash
# Start API server
docker run -d -p 8080:8080 zoom-recorder ./api-server.sh

# Control via HTTP
curl -X POST http://localhost:8080/join \
  -d '{"meeting_url": "...", "password": "..."}'

curl -X POST http://localhost:8080/start-recording
curl -X POST http://localhost:8080/stop-recording
```

## Recording Output

Recordings saved to `/recordings` mount:
- `meeting_YYYYMMDD_HHMMSS.mp4` - Full meeting recording
- Logs saved alongside for debugging

## Legal Note

⚠️ Only use on meetings you host or have explicit permission to record. Automated recording may violate Zoom Terms of Service.

## License

MIT