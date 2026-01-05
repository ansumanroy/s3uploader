#!/bin/bash
# Helper script to run awscurl in Docker container or system
# Usage: ./run-awscurl.sh [awscurl-args...]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_IMAGE="s3uploader-python:latest"

# Check if awscurl is available on system
if command -v awscurl &>/dev/null; then
    # Use system awscurl
    exec awscurl "$@"
elif command -v docker &>/dev/null && docker image inspect "$DOCKER_IMAGE" &>/dev/null 2>&1; then
    # Use awscurl from Docker container
    exec docker run --rm \
        -e AWS_ACCESS_KEY_ID \
        -e AWS_SECRET_ACCESS_KEY \
        -e AWS_SESSION_TOKEN \
        -e AWS_DEFAULT_REGION \
        "$DOCKER_IMAGE" \
        awscurl "$@"
else
    echo "Error: awscurl not found. Please:"
    echo "  1. Install awscurl: pip install awscurl"
    echo "  2. Or rebuild Docker image: docker build -t s3uploader-python:latest -f test-uploads/Dockerfile test-uploads/"
    exit 1
fi

