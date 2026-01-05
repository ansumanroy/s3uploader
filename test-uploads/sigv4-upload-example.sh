#!/bin/bash
# Example: Upload to S3 using SigV4 signing directly with curl
# This demonstrates how to use SigV4 signing without presigned URLs

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
    exit 1
fi

FILE_PATH=$1
S3_KEY=${2:-"${S3_UPLOAD_DIR:-uploads}/$(basename "$FILE_PATH")"}"

# Assume role first
echo "Step 1: Assuming role..."
source "$SCRIPT_DIR/assume-role.sh"

# Verify credentials
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Error: AWS credentials not set"
    exit 1
fi

# Method 1: Use AWS CLI (easiest - handles SigV4 automatically)
echo "Step 2: Uploading using AWS CLI (SigV4 signed automatically)..."
aws s3 cp "$FILE_PATH" "s3://$BUCKET_NAME/$S3_KEY" --region "$REGION"

if [ $? -eq 0 ]; then
    echo "✓ Upload successful!"
    exit 0
fi

# Method 2: Use awscurl if available (wraps curl with SigV4)
if command -v awscurl &>/dev/null; then
    echo "Step 2: Uploading using awscurl (SigV4 signing)..."
    FILE_SIZE=$(stat -f%z "$FILE_PATH" 2>/dev/null || stat -c%s "$FILE_PATH" 2>/dev/null)
    
    awscurl --service s3 \
        --region "$REGION" \
        -X PUT \
        --data-binary "@$FILE_PATH" \
        -H "Content-Length: $FILE_SIZE" \
        "https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com/${S3_KEY}"
    
    if [ $? -eq 0 ]; then
        echo "✓ Upload successful!"
        exit 0
    fi
fi

# Method 3: Manual SigV4 (complex - using helper script)
echo "Step 2: Uploading using manual SigV4 signing..."
echo "Note: This requires a proper SigV4 signing implementation"
echo "For production, use AWS CLI or awscurl instead"

exit 1

