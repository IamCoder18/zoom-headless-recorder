# zoom-headless-recorder

A reliable Docker-based solution for automated Zoom meeting joining and recording with CLI control.

## Quick Install (One-Line)

```bash
curl -sL https://raw.githubusercontent.com/IamCoder18/zoom-headless-recorder/master/install.sh | bash
```

Or using the CLI directly from npm:

```bash
npm install -g zoom-recorder-cli
zoom-rec --help
```

## Usage

```bash
# Join and record a meeting
zoom-rec run https://zoom.us/j/123456789 [passcode] [duration-seconds]

# Check status
zoom-rec status

# Interactive scheduling
zoom-rec schedule
```

## Architecture

- **Docker container** with Xvfb, Zoom client, ffmpeg, noVNC
- **CLI** (TypeScript) for all control
- **Environment-based config** stored in `~/.zoom-recorder/config.json`
- **GHCR** for container registry

## Configuration

Default config (`~/.zoom-recorder/config.json`):
```json
{
  "registry": "ghcr.io",
  "recordingsDir": "~/zoom-recordings",
  "apiPort": 8080,
  "vncPort": 6080,
  "meetingDuration": 3600
}
```

## Access (when recording)

- **noVNC**: http://localhost:6080 (browser-based virtual desktop)
- **API**: http://localhost:8080
- **Recordings**: `~/zoom-recordings/meeting_*.mp4`

## Container Lifecycle

The CLI manages containers intelligently:
1. Starts on demand (via `zoom-rec run`)
2. Records for specified duration
3. Auto-stops when done (or via Ctrl+C)
4. No persistent container = no resource waste

## Local Development

```bash
# Build the CLI from source
cd cli
npm install
npm run build

# Link globally
sudo ln -s $(pwd)/dist/index.js /usr/local/bin/zoom-rec

# Build the Docker image
cd ..
docker build -t zoom-recorder .
```

## Legal Note

⚠️ Only use on meetings you host or have explicit permission to record. Automated recording may violate Zoom Terms of Service.

## License

MIT