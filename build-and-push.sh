#!/bin/bash
#
# DistributeX Worker Docker Build and Push Script
# Usage: ./build-and-push.sh [version]
#

set -e

VERSION="${1:-latest}"
IMAGE_NAME="distributex/worker"
PLATFORMS="linux/amd64,linux/arm64,linux/arm/v7"

echo "🐳 Building DistributeX Worker Docker Image"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Version: $VERSION"
echo "Image: $IMAGE_NAME:$VERSION"
echo "Platforms: $PLATFORMS"
echo ""

# Check if logged into Docker Hub
if ! docker info | grep -q "Username"; then
    echo "❌ Not logged into Docker Hub"
    echo "Run: docker login"
    exit 1
fi

# Build for multiple architectures
echo "🔨 Building multi-architecture image..."
docker buildx build \
    --platform $PLATFORMS \
    --tag $IMAGE_NAME:$VERSION \
    --tag $IMAGE_NAME:latest \
    --push \
    .

echo ""
echo "✅ Successfully built and pushed:"
echo "   - $IMAGE_NAME:$VERSION"
echo "   - $IMAGE_NAME:latest"
echo ""
echo "📦 Image size:"
docker manifest inspect $IMAGE_NAME:$VERSION | grep size | head -1

echo ""
echo "🚀 Test the image:"
echo "   docker run -it --rm $IMAGE_NAME:$VERSION --api-key YOUR_KEY"
