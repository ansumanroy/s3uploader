#!/bin/bash
# Simple upload using AWS CLI (automatic SigV4 signing)
# This uses AWS CLI which automatically signs all requests with SigV4
# Usage: ./simple-upload-sigv4-direct.sh <file-path> [s3-key]

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

# Get file info
FILE_SIZE=$(stat -f%z "$FILE_PATH" 2>/dev/null || stat -c%s "$FILE_PATH" 2>/dev/null)
FILE_TYPE=$(file --mime-type -b "$FILE_PATH" 2>/dev/null || echo "application/octet-stream")

echo "Step 2: File information"
echo "  File: $FILE_PATH"
echo "  Size: $(numfmt --to=iec-i --suffix=B $FILE_SIZE)"
echo "  Type: $FILE_TYPE"
echo "  S3 Key: s3://$BUCKET_NAME/$S3_KEY"

# Upload using AWS CLI (automatically uses SigV4 signing)
echo "Step 3: Uploading file using AWS CLI (SigV4 signed automatically)..."
aws s3 cp "$FILE_PATH" "s3://$BUCKET_NAME/$S3_KEY" \
    --region "$REGION" \
    --content-type "$FILE_TYPE" \
    --only-show-errors

if [ $? -eq 0 ]; then
    echo "✓ Upload successful!"
    echo "  File uploaded to: s3://$BUCKET_NAME/$S3_KEY"
    echo "  URL: https://s3.$REGION.amazonaws.com/$BUCKET_NAME/$S3_KEY"
else
    echo "✗ Upload failed"
    exit 1
fi

