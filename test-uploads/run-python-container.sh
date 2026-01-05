#!/bin/bash
# Helper script to run Python scripts in Docker container
# Usage: ./run-python-container.sh <python-script> [script-args...]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_IMAGE="s3uploader-python:latest"
PYTHON_SCRIPT=$1

if [ $# -lt 1 ]; then
    echo "Usage: $0 <python-script> [script-args...]"
    echo "Example: $0 generate-presigned-url.py --bucket mybucket --key mykey --region us-east-1"
    exit 1
fi

# Check if script exists
if [ ! -f "$SCRIPT_DIR/$PYTHON_SCRIPT" ]; then
    echo "Error: Python script not found: $PYTHON_SCRIPT"
    exit 1
fi

# Check if Docker image exists, if not build it
if ! docker image inspect "$DOCKER_IMAGE" &>/dev/null; then
    echo "Docker image not found. Building $DOCKER_IMAGE..."
    docker build -t "$DOCKER_IMAGE" -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to build Docker image"
        exit 1
    fi
    echo "✓ Docker image built successfully"
fi

# Shift to get remaining arguments for the Python script
shift

# Run Python script in Docker container
# Mount script directory as volume, pass AWS credentials as environment variables
docker run --rm \
    -v "$SCRIPT_DIR:/app" \
    -e AWS_ACCESS_KEY_ID \
    -e AWS_SECRET_ACCESS_KEY \
    -e AWS_SESSION_TOKEN \
    -e AWS_DEFAULT_REGION \
    -w /app \
    "$DOCKER_IMAGE" \
    python3 "$PYTHON_SCRIPT" "$@"

