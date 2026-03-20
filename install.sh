#!/bin/bash
# One-line installer for Zoom Recorder CLI
# Usage: curl -sL https://raw.githubusercontent.com/IamCoder18/zoom-headless-recorder/master/install.sh | bash

set -e

echo "Installing Zoom Recorder CLI..."

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is required. Install from https://docs.docker.com/get-docker"
    exit 1
fi

# Check gh
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI is required. Install from https://cli.github.com"
    exit 1
fi

# Create temp dir
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Get GitHub token
GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo "")
if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: Not logged into GitHub. Run 'gh auth login' first."
    exit 1
fi

# Get username
GITHUB_USER=$(gh api user --jq .login)

# Login to GHCR
echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USER" --password-stdin 2>/dev/null || true

# Pull or build image
IMAGE_NAME="ghcr.io/${GITHUB_USER}/zoom-recorder:latest"
if docker pull "$IMAGE_NAME" 2>/dev/null; then
    echo "Using pre-built image"
else
    echo "Building image (this may take a few minutes)..."
    # Clone and build would go here in full version
    echo "Error: Image not found. Clone repo and run: cd cli && npm install && npm run build"
    exit 1
fi

# Create config
CONFIG_DIR="${HOME}/.zoom-recorder"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/config.json" << EOF
{
  "registry": "ghcr.io",
  "recordingsDir": "${HOME}/zoom-recordings",
  "apiPort": 8080,
  "vncPort": 6080,
  "meetingDuration": 3600
}
EOF

# Create wrapper script
WRAPPER="/usr/local/bin/zoom-rec"
sudo tee "$WRAPPER" > /dev/null << 'WRAPPER_EOF'
#!/bin/bash
CONFIG_DIR="${HOME}/.zoom-recorder"
CONFIG_FILE="${CONFIG_DIR}/config.json"
IMAGE_NAME="ghcr.io/REPLACE_USER/zoom-recorder:latest"

if [ -f "$CONFIG_FILE" ]; then
    source <(grep -E '^[^#]*=' "$CONFIG_FILE" | sed 's/=/="/;s/$/"/')
fi

RECORDINGS_DIR="${recordingsDir:-${HOME}/zoom-recordings}"
API_PORT="${apiPort:-8080}"
VNC_PORT="${vncPort:-6080}"

case "${1:-}" in
    run)
        shift
        MEETING_URL="${1:-}"
        PASSWORD="${2:-}"
        DURATION="${3:-3600}"
        [ -z "$MEETING_URL" ] && { echo "Usage: zoom-rec run <url> [password] [duration]"; exit 1; }
        docker run --rm -it \
            -v "$RECORDINGS_DIR:/recordings" \
            -p "$API_PORT:8080" \
            -p "$VNC_PORT:6080" \
            -e ZOOM_MEETING_URL="$MEETING_URL" \
            -e ZOOM_PASSWORD="$PASSWORD" \
            -e ZOOM_MEETING_DURATION="$DURATION" \
            "$IMAGE_NAME" \
            /usr/local/bin/start-recording.sh
        ;;
    install)
        echo "Already installed!"
        ;;
    status)
        docker ps --filter "name=zoom-recorder" --format "{{.Status}}" 2>/dev/null || echo "Not running"
        ;;
    *)
        echo "Zoom Recorder CLI"
        echo ""
        echo "Commands:"
        echo "  install     Install CLI and build image"
        echo "  run <url>   Join meeting and record"
        echo "  status      Check if recorder is running"
        echo ""
        echo "Examples:"
        echo "  zoom-rec run https://zoom.us/j/123456789 passcode 3600"
        ;;
esac
WRAPPER_EOF

# Fix image name in wrapper
sudo sed -i "s|REPLACE_USER|${GITHUB_USER}|g" "$WRAPPER"
sudo chmod +x "$WRAPPER"

# Create recordings dir
mkdir -p "${HOME}/zoom-recordings"

echo ""
echo "✅ Installed! Run: zoom-rec --help"
echo ""
echo "Quick start:"
echo "  zoom-rec run https://zoom.us/j/123456789"
echo ""
echo "Files saved to: ${HOME}/zoom-recordings"