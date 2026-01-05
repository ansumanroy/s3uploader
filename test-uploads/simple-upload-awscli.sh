#!/bin/bash
# Simple file upload to S3 using awscurl with SigV4 signing
# Usage: ./simple-upload-awscli.sh <file-path> [s3-key]

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "Error: config.sh not found"
    exit 1
fi

# Check arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <file-path> [s3-key]"
    echo "Example: $0 ./myfile.txt uploads/myfile.txt"
    exit 1
fi

FILE_PATH=$1
S3_KEY=${2:-"${S3_UPLOAD_DIR:-uploads}/$(basename "$FILE_PATH")"}

# Validate file exists
if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File not found: $FILE_PATH"
    exit 1
fi

# Assume role first
echo "Step 1: Assuming role..."
source "$SCRIPT_DIR/assume-role.sh"

# Check if role was assumed successfully
if [ -z "$AWS_SESSION_TOKEN" ]; then
    echo "Error: Failed to assume role"
    exit 1
fi

# Verify credentials are exported (for debugging)
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Error: AWS credentials not exported after role assumption"
    exit 1
fi

# Get file info
FILE_SIZE=$(stat -f%z "$FILE_PATH" 2>/dev/null || stat -c%s "$FILE_PATH" 2>/dev/null)
FILE_TYPE=$(file --mime-type -b "$FILE_PATH" 2>/dev/null || echo "application/octet-stream")

echo "Step 2: File information"
echo "  File: $FILE_PATH"
echo "  Size: $(numfmt --to=iec-i --suffix=B $FILE_SIZE)"
echo "  Type: $FILE_TYPE"
echo "  S3 Key: s3://$BUCKET_NAME/$S3_KEY"

# Verify credentials are set
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_SESSION_TOKEN" ]; then
    echo "Error: AWS credentials not properly set after role assumption"
    echo "  AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:+set}"
    echo "  AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:+set}"
    echo "  AWS_SESSION_TOKEN: ${AWS_SESSION_TOKEN:+set}"
    exit 1
fi

# Upload file using awscurl (SigV4 signing)
echo "Step 3: Uploading file using awscurl (SigV4 signed)..."

# Use helper script to run awscurl (handles Docker/system detection)
AWSCURL_HELPER="$SCRIPT_DIR/run-awscurl.sh"

if [ ! -f "$AWSCURL_HELPER" ]; then
    echo "Error: run-awscurl.sh helper script not found"
    exit 1
fi

# Build S3 URL
S3_URL="https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com/${S3_KEY}"

echo "  Uploading to: $S3_URL"

# For Docker, we need to mount the file directory
if command -v docker &>/dev/null && ! command -v awscurl &>/dev/null; then
    # Docker mode - mount file directory
    FILE_DIR=$(dirname "$FILE_PATH")
    FILE_NAME=$(basename "$FILE_PATH")
    
    UPLOAD_OUTPUT=$(docker run --rm \
        -v "$FILE_DIR:/data" \
        -e AWS_ACCESS_KEY_ID \
        -e AWS_SECRET_ACCESS_KEY \
        -e AWS_SESSION_TOKEN \
        -e AWS_DEFAULT_REGION \
        s3uploader-python:latest \
        awscurl --service s3 \
            --region "$REGION" \
            -X PUT \
            --data-binary "@/data/$FILE_NAME" \
            -H "Content-Type: $FILE_TYPE" \
            --write-out "\nHTTP Status: %{http_code}" \
            --silent \
            --show-error \
            "$S3_URL" 2>&1)
else
    # System awscurl or helper script
    UPLOAD_OUTPUT=$("$AWSCURL_HELPER" --service s3 \
        --region "$REGION" \
        -X PUT \
        --data-binary "@$FILE_PATH" \
        -H "Content-Type: $FILE_TYPE" \
        --write-out "\nHTTP Status: %{http_code}" \
        --silent \
        --show-error \
        "$S3_URL" 2>&1)
fi

UPLOAD_EXIT_CODE=$?
HTTP_CODE=$(echo "$UPLOAD_OUTPUT" | grep "HTTP Status:" | cut -d' ' -f3 || echo "")

# Check if upload was successful (awscurl returns 0 on success, HTTP 200)
if [ "$UPLOAD_EXIT_CODE" -eq 0 ]; then
    echo "✓ Upload successful!"
    echo "  File uploaded to: s3://$BUCKET_NAME/$S3_KEY"
    echo "  URL: https://s3.$REGION.amazonaws.com/$BUCKET_NAME/$S3_KEY"
elif [ "$HTTP_CODE" == "200" ]; then
    echo "✓ Upload successful! (HTTP 200)"
    echo "  File uploaded to: s3://$BUCKET_NAME/$S3_KEY"
    echo "  URL: https://s3.$REGION.amazonaws.com/$BUCKET_NAME/$S3_KEY"
else
    echo "✗ Upload failed"
    if [ -n "$UPLOAD_OUTPUT" ]; then
        echo "$UPLOAD_OUTPUT"
    fi
    exit 1
fi

# Upload file using awscurl (SigV4 signing)
echo "Step 4: Uploading file using awscurl (SigV4 signed)..."

# Check if awscurl is available (try Docker container first, then system)
AWSCURL_CMD=""
if command -v awscurl &>/dev/null; then
    AWSCURL_CMD="awscurl"
elif command -v docker &>/dev/null; then
    # Try to use awscurl from Docker container
    DOCKER_IMAGE="s3uploader-python:latest"
    if docker image inspect "$DOCKER_IMAGE" &>/dev/null 2>&1; then
        AWSCURL_CMD="docker"
    fi
fi

if [ -z "$AWSCURL_CMD" ]; then
    echo "Error: awscurl not found. Please:"
    echo "  1. Install awscurl: pip install awscurl"
    echo "  2. Or rebuild Docker image: docker build -t s3uploader-python:latest -f test-uploads/Dockerfile test-uploads/"
    exit 1
fi

# Build S3 URL
S3_URL="https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com/${S3_KEY}"

echo "  Uploading to: $S3_URL"

# Upload using awscurl with SigV4 signing
if [ "$AWSCURL_CMD" == "docker" ]; then
    # Docker version - need to pass file as volume mount
    FILE_DIR=$(dirname "$FILE_PATH")
    FILE_NAME=$(basename "$FILE_PATH")
    
    UPLOAD_OUTPUT=$(docker run --rm \
        -v "$FILE_DIR:/data" \
        -e AWS_ACCESS_KEY_ID \
        -e AWS_SECRET_ACCESS_KEY \
        -e AWS_SESSION_TOKEN \
        -e AWS_DEFAULT_REGION \
        "$DOCKER_IMAGE" \
        awscurl --service s3 \
            --region "$REGION" \
            -X PUT \
            --data-binary "@/data/$FILE_NAME" \
            -H "Content-Type: $FILE_TYPE" \
            --write-out "\nHTTP Status: %{http_code}" \
            --silent \
            --show-error \
            "$S3_URL" 2>&1)
    
    UPLOAD_EXIT_CODE=${PIPESTATUS[0]}
else
    # Direct awscurl command (uses credentials from environment)
    UPLOAD_OUTPUT=$(awscurl --service s3 \
        --region "$REGION" \
        -X PUT \
        --data-binary "@$FILE_PATH" \
        -H "Content-Type: $FILE_TYPE" \
        --write-out "\nHTTP Status: %{http_code}" \
        --silent \
        --show-error \
        "$S3_URL" 2>&1)
    
    UPLOAD_EXIT_CODE=$?
fi

HTTP_CODE=$(echo "$UPLOAD_OUTPUT" | grep "HTTP Status:" | cut -d' ' -f3)

# Check if upload was successful (awscurl returns 0 on success, HTTP 200)
if [ "$UPLOAD_EXIT_CODE" -eq 0 ] || [ "$HTTP_CODE" == "200" ]; then
    echo "✓ Upload successful!"
    echo "  File uploaded to: s3://$BUCKET_NAME/$S3_KEY"
    echo "  URL: https://s3.$REGION.amazonaws.com/$BUCKET_NAME/$S3_KEY"
else
    echo "✗ Upload failed"
    if [ -n "$UPLOAD_OUTPUT" ]; then
        echo "$UPLOAD_OUTPUT"
    fi
    exit 1
fi

