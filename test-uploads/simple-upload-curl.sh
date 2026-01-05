#!/bin/bash
# Simple file upload to S3 using presigned URLs with curl (hybrid approach)
# Uses AWS CLI for presigned URL generation, curl for upload
# Usage: ./simple-upload-curl.sh <file-path> [s3-key]

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

# Assume role first (uses AWS CLI)
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

# Verify credentials are set
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_SESSION_TOKEN" ]; then
    echo "Error: AWS credentials not properly set after role assumption"
    exit 1
fi

# Generate presigned URL using s3api for PUT operation
echo "Step 3: Generating presigned URL (using AWS CLI)..."
# Try aws s3api presign first (requires --operation for PUT)
PRESIGNED_URL=$(aws s3api presign \
    --bucket "$BUCKET_NAME" \
    --key "$S3_KEY" \
    --expires-in ${PRESIGNED_URL_EXPIRATION:-3600} \
    --region "$REGION" \
    --operation put-object 2>&1)

# If that fails, try aws s3 presign (may work in some AWS CLI versions)
if [ $? -ne 0 ] || [[ "$PRESIGNED_URL" =~ [Ee]rror ]]; then
    echo "  Note: s3api presign failed, trying s3 presign..."
    PRESIGNED_URL=$(aws s3 presign "s3://$BUCKET_NAME/$S3_KEY" \
        --expires-in ${PRESIGNED_URL_EXPIRATION:-3600} \
        --region "$REGION" 2>&1)
fi

if [ $? -ne 0 ] || [[ "$PRESIGNED_URL" =~ [Ee]rror ]]; then
    echo "Error generating presigned URL:"
    echo "$PRESIGNED_URL"
    exit 1
fi

# Clean up the URL
PRESIGNED_URL=$(echo "$PRESIGNED_URL" | head -1 | tr -d '"' | tr -d "'" | tr -d '\n' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

echo "  Presigned URL generated (expires in ${PRESIGNED_URL_EXPIRATION:-3600} seconds)"

# Upload file using curl
echo "Step 4: Uploading file (using curl)..."
HTTP_CODE=$(curl -w "%{http_code}" \
    -X PUT \
    --url "$PRESIGNED_URL" \
    --data-binary @"$FILE_PATH" \
    --silent \
    --show-error \
    -o /dev/null 2>&1)

if [ "$HTTP_CODE" == "200" ]; then
    echo "✓ Upload successful! (HTTP $HTTP_CODE)"
    echo "  File uploaded to: s3://$BUCKET_NAME/$S3_KEY"
    echo "  URL: https://s3.$REGION.amazonaws.com/$BUCKET_NAME/$S3_KEY"
else
    echo "✗ Upload failed with HTTP status: $HTTP_CODE"
    exit 1
fi

