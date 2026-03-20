#!/bin/bash
# Build and push multiarch Docker image to GHCR
# Usage: ./build.sh
#
# Requirements:
#   - Docker with buildx (docker buildx create --name mybuilder --use)
#   - gh CLI logged in (gh auth login)
#   - GHCR push permissions

set -e

echo "╔═══════════════════════════════════════════════════════╗"
echo "║        Building Multiarch Docker Image              ║"
echo "╚═══════════════════════════════════════════════════════╝"

# Get GitHub user
GITHUB_USER=$(gh api user --jq .login)
IMAGE_NAME="ghcr.io/${GITHUB_USER}/zoom-recorder:latest"

echo "GitHub user: $GITHUB_USER"
echo "Image: $IMAGE_NAME"
echo ""

# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is required"
    exit 1
fi

# Setup buildx if not exists
if ! docker buildx inspect mybuilder &> /dev/null; then
    echo "Creating buildx builder..."
    docker buildx create --name mybuilder --use
fi

docker buildx use mybuilder

# Login to GHCR
echo "Logging into GHCR..."
echo "$(gh auth token)" | docker login ghcr.io -u "$GITHUB_USER" --password-stdin 2>/dev/null

# Build and push multiarch
echo "Building multiarch image (amd64, arm64, arm/v7)..."
docker buildx build \
    --platforms=linux/amd64,linux/arm64,linux/arm/v7 \
    --push \
    -t "$IMAGE_NAME" .

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║                    ✅ Done!                         ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "Image pushed: $IMAGE_NAME"
echo ""
echo "Users can now install with:"
echo "  curl -sL https://raw.githubusercontent.com/${GITHUB_USER}/zoom-headless-recorder/master/install.sh | bash"