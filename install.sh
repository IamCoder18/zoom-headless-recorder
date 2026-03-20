#!/bin/bash
# One-line installer for Zoom Recorder CLI
# Usage: curl -sL https://raw.githubusercontent.com/IamCoder18/zoom-headless-recorder/master/install.sh | bash
#
# This script will:
# 1. Check prerequisites (Docker, gh)
# 2. Pull the pre-built multiarch Docker image from GHCR
# 3. Install the CLI wrapper

set -e

echo "╔═══════════════════════════════════════════════════════╗"
echo "║          Zoom Recorder CLI Installer                 ║"
echo "╚═══════════════════════════════════════════════════════╝"

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

# Get GitHub user and token
GITHUB_USER=$(gh api user --jq .login)
GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo "")

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: Not logged into GitHub. Run 'gh auth login' first."
    exit 1
fi

IMAGE_NAME="ghcr.io/${GITHUB_USER}/zoom-recorder:latest"
REGISTRY="ghcr.io"

echo ""
echo "GitHub user: $GITHUB_USER"
echo "Image: $IMAGE_NAME"
echo ""

# Login to GHCR
echo "Logging into GHCR..."
echo "$GITHUB_TOKEN" | docker login $REGISTRY -u "$GITHUB_USER" --password-stdin 2>/dev/null

# Pull pre-built image
echo "Pulling Docker image..."
docker pull "$IMAGE_NAME"

echo "Image pulled successfully!"

# Create config
CONFIG_DIR="${HOME}/.zoom-recorder"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/config.json" << EOF
{
  "registry": "${REGISTRY}",
  "recordingsDir": "${HOME}/zoom-recordings",
  "apiPort": 8080,
  "vncPort": 6080,
  "meetingDuration": 3600,
  "prepBuffer": 60,
  "joinBuffer": 300,
  "recordOffset": 300,
  "leaveOffset": 0,
  "recordAfter": 600
}
EOF

# Create wrapper script
echo "Installing CLI wrapper..."
WRAPPER="/usr/local/bin/zoom-rec"

cat > /tmp/zoom-rec-wrapper << WRAPPER_EOF
#!/bin/bash
CONFIG_DIR="\${HOME}/.zoom-recorder"
CONFIG_FILE="\${CONFIG_DIR}/config.json"
IMAGE_NAME="${IMAGE_NAME}"

# Load config if exists
if [ -f "\$CONFIG_FILE" ]; then
    RECORDINGS_DIR="\$(grep recordingsDir "\$CONFIG_FILE" | cut -d'"' -f4)"
    API_PORT="\$(grep apiPort "\$CONFIG_FILE" | grep -o '[0-9]*')"
    VNC_PORT="\$(grep vncPort "\$CONFIG_FILE" | grep -o '[0-9]*')"
    MEETING_DURATION="\$(grep meetingDuration "\$CONFIG_FILE" | grep -o '[0-9]*')"
    PREP_BUFFER="\$(grep prepBuffer "\$CONFIG_FILE" | grep -o '[0-9-]*' | head -1)"
    JOIN_BUFFER="\$(grep joinBuffer "\$CONFIG_FILE" | grep -o '[0-9-]*' | head -1)"
    RECORD_OFFSET="\$(grep recordOffset "\$CONFIG_FILE" | grep -o '[0-9-]*' | head -1)"
    LEAVE_OFFSET="\$(grep leaveOffset "\$CONFIG_FILE" | grep -o '[0-9-]*' | head -1)"
    RECORD_AFTER="\$(grep recordAfter "\$CONFIG_FILE" | grep -o '[0-9-]*' | head -1)"
fi

RECORDINGS_DIR="\${RECORDINGS_DIR:-\${HOME}/zoom-recordings}"
API_PORT="\${API_PORT:-8080}"
VNC_PORT="\${VNC_PORT:-6080}"
MEETING_DURATION="\${MEETING_DURATION:-3600}"
PREP_BUFFER="\${PREP_BUFFER:-60}"
JOIN_BUFFER="\${JOIN_BUFFER:-300}"
RECORD_OFFSET="\${RECORD_OFFSET:-300}"
LEAVE_OFFSET="\${LEAVE_OFFSET:-0}"
RECORD_AFTER="\${RECORD_AFTER:-600}"

case "\${1:-}" in
    run)
        shift
        MEETING_URL="\${1:-}"
        PASSWORD="\${2:-}"
        DURATION="\${3:-}"
        
        [ -z "\$MEETING_URL" ] && { echo "Usage: zoom-rec run <url> [password] [duration] [prep] [join] [recordOffset] [leaveOffset] [recordAfter]"; exit 1; }
        
        PREP_BUFFER="\${4:-\${PREP_BUFFER}}"
        JOIN_BUFFER="\${5:-\${JOIN_BUFFER}}"
        RECORD_OFFSET="\${6:-\${RECORD_OFFSET}}"
        LEAVE_OFFSET="\${7:-\${LEAVE_OFFSET}}"
        RECORD_AFTER="\${8:-\${RECORD_AFTER}}"
        
        echo "Starting Zoom recorder..."
        echo "  Meeting: \$MEETING_URL"
        echo "  Duration: \${DURATION:-\${MEETING_DURATION}}s"
        
        docker run --rm -it \
            -v "\$RECORDINGS_DIR:/recordings" \
            -p "\${API_PORT}:8080" \
            -p "\${VNC_PORT}:6080" \
            -e ZOOM_MEETING_URL="\$MEETING_URL" \
            -e ZOOM_PASSWORD="\$PASSWORD" \
            -e ZOOM_MEETING_DURATION="\${DURATION:-\${MEETING_DURATION}}" \
            -e ZOOM_PREP_BUFFER="\$PREP_BUFFER" \
            -e ZOOM_JOIN_BUFFER="\$JOIN_BUFFER" \
            -e ZOOM_RECORD_OFFSET="\$RECORD_OFFSET" \
            -e ZOOM_LEAVE_OFFSET="\$LEAVE_OFFSET" \
            -e ZOOM_RECORD_AFTER="\$RECORD_AFTER" \
            "\$IMAGE_NAME" \
            /usr/local/bin/start-recording.sh
        ;;
    install)
        echo "Already installed! Pulling latest image..."
        docker pull "$IMAGE_NAME"
        ;;
    update)
        echo "Pulling latest image..."
        docker pull "$IMAGE_NAME"
        ;;
    status)
        docker ps --filter "name=zoom-recorder" --format "{{.Status}}" 2>/dev/null || echo "Not running"
        ;;
    config)
        \$EDITOR "\$CONFIG_FILE" 2>/dev/null || nano "\$CONFIG_FILE" 2>/dev/null || cat "\$CONFIG_FILE"
        ;;
    --help|-h|"")
        echo "Zoom Recorder CLI - \${IMAGE_NAME}"
        echo ""
        echo "Commands:"
        echo "  run <url> [pwd] [dur] [prep] [join] [rec] [leave] [after]  Join & record"
        echo "  update                         Pull latest image"
        echo "  status                         Check if recorder is running"
        echo "  config                         Edit configuration"
        echo "  install                        Re-run installer"
        echo ""
        echo "Timing (defaults):"
        echo "  prepBuffer=60, joinBuffer=300, recordOffset=300, leaveOffset=0, recordAfter=600"
        echo ""
        echo "Examples:"
        echo "  zoom-rec run https://zoom.us/j/123456789"
        echo "  zoom-rec run https://zoom.us/j/123 passcode 3600 60 600 300 -300 1200"
        ;;
esac
WRAPPER_EOF

sudo mv /tmp/zoom-rec-wrapper "$WRAPPER"
sudo chmod +x "$WRAPPER"

# Create recordings dir
mkdir -p "${HOME}/zoom-recordings"

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║                    ✅ Installed!                     ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "Image: $IMAGE_NAME"
echo "CLI: zoom-rec"
echo "Recordings: ${HOME}/zoom-recordings"
echo ""
echo "Quick start:"
echo "  zoom-rec run https://zoom.us/j/123456789"
echo ""
echo "For help:"
echo "  zoom-rec --help"