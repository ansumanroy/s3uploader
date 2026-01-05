#!/bin/bash
# Simple file upload to S3 using presigned URLs with AWS CLI
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

# Generate presigned URL using s3api for PUT operation
# Note: aws s3 presign generates GET URLs - we MUST use s3api presign for PUT
echo "Step 3: Generating presigned URL..."

# Try Python/boto3 method first (more reliable with temporary credentials)
PRESIGNED_URL=""
PYTHON_SCRIPT="$SCRIPT_DIR/generate-presigned-url.py"
VENV_PYTHON="$SCRIPT_DIR/venv/bin/python3"

# Check for Python with boto3 - prefer venv if it exists
PYTHON_CMD=""
if [ -f "$VENV_PYTHON" ] && "$VENV_PYTHON" -c "import boto3" 2>/dev/null; then
    PYTHON_CMD="$VENV_PYTHON"
elif command -v python3 &>/dev/null && python3 -c "import boto3" 2>/dev/null; then
    PYTHON_CMD="python3"
fi

if [ -f "$PYTHON_SCRIPT" ] && [ -n "$PYTHON_CMD" ]; then
    echo "  Using Python/boto3 to generate presigned URL..."
    PRESIGNED_URL=$("$PYTHON_CMD" "$PYTHON_SCRIPT" \
        --bucket "$BUCKET_NAME" \
        --key "$S3_KEY" \
        --region "$REGION" \
        --expires-in ${PRESIGNED_URL_EXPIRATION:-3600} 2>&1)
    
    if [ $? -eq 0 ] && [[ "$PRESIGNED_URL" =~ ^https:// ]]; then
        echo "  ✓ Presigned URL generated using Python/boto3"
    else
        echo "  Python method failed, trying AWS CLI..."
        PRESIGNED_URL=""
    fi
fi

# Fallback to AWS CLI if Python method didn't work
if [ -z "$PRESIGNED_URL" ] || [[ ! "$PRESIGNED_URL" =~ ^https:// ]]; then
    echo "  Using AWS CLI to generate presigned URL..."
    
    # Try aws s3api presign with --operation put-object first
    TEMP_URL=$(aws s3api presign \
        --bucket "$BUCKET_NAME" \
        --key "$S3_KEY" \
        --expires-in ${PRESIGNED_URL_EXPIRATION:-3600} \
        --region "$REGION" \
        --operation put-object 2>&1)
    
    PRESIGN_EXIT_CODE=$?
    
    # If that failed or doesn't look like a URL, try without --operation
    # Some AWS CLI versions may have different syntax
    if [ $PRESIGN_EXIT_CODE -ne 0 ] || [[ "$TEMP_URL" =~ ^[Ee]rror ]] || [[ "$TEMP_URL" =~ ^usage: ]] || [[ ! "$TEMP_URL" =~ ^https:// ]]; then
        echo "  Note: Trying alternative presign syntax..."
        TEMP_URL=$(aws s3api presign \
            --bucket "$BUCKET_NAME" \
            --key "$S3_KEY" \
            --expires-in ${PRESIGNED_URL_EXPIRATION:-3600} \
            --region "$REGION" 2>&1)
        PRESIGN_EXIT_CODE=$?
    fi
    
    # Check for errors
    if [ $PRESIGN_EXIT_CODE -ne 0 ] || [[ "$TEMP_URL" =~ ^[Ee]rror ]] || [[ "$TEMP_URL" =~ ^usage: ]]; then
        echo "Error: Failed to generate presigned URL with aws s3api presign"
        echo "$TEMP_URL"
        echo ""
        echo "This is likely because your AWS CLI version doesn't support --operation with presign."
        echo "Please install boto3 for reliable presigned URL generation:"
        echo "  pip3 install boto3"
        echo ""
        echo "Or upgrade AWS CLI:"
        echo "  pip3 install --upgrade awscli"
        exit 1
    fi
    
    # Clean up the URL - get the actual URL, handling any extra output
    # The URL should be the first line that starts with https://
    PRESIGNED_URL=$(echo "$TEMP_URL" | grep -oE 'https://[^[:space:]]+' | head -1)
    
    # If grep didn't work, try simpler extraction
    if [ -z "$PRESIGNED_URL" ]; then
        PRESIGNED_URL=$(echo "$TEMP_URL" | head -1 | tr -d '"' | tr -d "'" | tr -d '\n' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi
    
    # Warn if URL doesn't look like a PUT URL
    if [[ "$PRESIGNED_URL" =~ ^https:// ]] && [[ ! "$PRESIGNED_URL" =~ X-Amz-Expires ]]; then
        echo "  Warning: Presigned URL might not be for PUT operation"
    fi
fi

# Validate URL looks correct
if [[ ! "$PRESIGNED_URL" =~ ^https:// ]]; then
    echo "Error: Generated URL doesn't look valid: $PRESIGNED_URL"
    exit 1
fi

echo "  Presigned URL generated (expires in ${PRESIGNED_URL_EXPIRATION:-3600} seconds)"
echo "  URL: ${PRESIGNED_URL:0:100}..."

# Upload file using curl
# Critical: Use the exact URL without any modification
# Don't add Content-Type or other headers unless they're in the signature
echo "Step 4: Uploading file..."
# Use -T (upload file) which automatically uses PUT method
# Don't add -X PUT as -T already implies PUT
# Use --url to ensure curl doesn't modify the URL
UPLOAD_OUTPUT=$(curl -w "\nHTTP Status: %{http_code}" \
    -T "$FILE_PATH" \
    --url "$PRESIGNED_URL" \
    --silent \
    --show-error \
    2>&1)

HTTP_CODE=$(echo "$UPLOAD_OUTPUT" | grep "HTTP Status:" | cut -d' ' -f3)

if [ "$HTTP_CODE" == "200" ]; then
    echo "✓ Upload successful!"
    echo "  File uploaded to: s3://$BUCKET_NAME/$S3_KEY"
    echo "  URL: https://s3.$REGION.amazonaws.com/$BUCKET_NAME/$S3_KEY"
else
    echo "✗ Upload failed with HTTP status: $HTTP_CODE"
    echo "$UPLOAD_OUTPUT"
    exit 1
fi

