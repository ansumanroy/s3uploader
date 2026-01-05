#!/bin/bash
# Multipart file upload to S3 using presigned URLs (SigV4 signed) with AWS CLI
# Note: Multipart uploads require presigned URLs (generated via SigV4)
# This script uses direct AWS credentials (from environment or ~/.aws/credentials)
# Usage: ./multipart-upload-awscli-direct.sh <file-path> [s3-key] [part-size-mb]

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
    echo "Usage: $0 <file-path> [s3-key] [part-size-mb]"
    echo "Example: $0 ./large-file.mp4 uploads/video.mp4 50"
    exit 1
fi

FILE_PATH=$1
S3_KEY=${2:-"${S3_UPLOAD_DIR:-uploads}/$(basename "$FILE_PATH")"}
PART_SIZE_MB=${3:-$((${MULTIPART_PART_SIZE:-52428800} / 1024 / 1024))}

# Convert MB to bytes
PART_SIZE=$((PART_SIZE_MB * 1024 * 1024))

# Validate minimum part size (5MB)
if [ $PART_SIZE -lt 5242880 ]; then
    echo "Error: Part size must be at least 5MB"
    exit 1
fi

# Validate file exists
if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File not found: $FILE_PATH"
    exit 1
fi

# Set up AWS credentials (if USER_ACCESS_KEY is provided in config, use it; otherwise use default AWS credentials)
if [ -n "$USER_ACCESS_KEY" ] && [ "$USER_ACCESS_KEY" != "YOUR_ACCESS_KEY" ]; then
    export AWS_ACCESS_KEY_ID="$USER_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$USER_SECRET_KEY"
    export AWS_DEFAULT_REGION="${REGION:-us-east-1}"
    echo "Using credentials from config.sh"
else
    export AWS_DEFAULT_REGION="${REGION:-us-east-1}"
    echo "Using default AWS credentials (from environment or ~/.aws/credentials)"
fi

# Get file info
FILE_SIZE=$(stat -f%z "$FILE_PATH" 2>/dev/null || stat -c%s "$FILE_PATH" 2>/dev/null)
FILE_TYPE=$(file --mime-type -b "$FILE_PATH" 2>/dev/null || echo "application/octet-stream")
TOTAL_PARTS=$(( ($FILE_SIZE + $PART_SIZE - 1) / $PART_SIZE ))

echo "Step 1: File information"
echo "  File: $FILE_PATH"
echo "  Size: $(numfmt --to=iec-i --suffix=B $FILE_SIZE)"
echo "  Type: $FILE_TYPE"
echo "  S3 Key: s3://$BUCKET_NAME/$S3_KEY"
echo "  Part size: ${PART_SIZE_MB}MB"
echo "  Total parts: $TOTAL_PARTS"

# Check if multipart upload is needed
if [ $TOTAL_PARTS -eq 1 ]; then
    echo "Note: File is small enough for single upload. Consider using simple-upload-awscli.sh"
fi

# Initiate multipart upload
echo "Step 2: Initiating multipart upload..."
INITIATE_OUTPUT=$(aws s3api create-multipart-upload \
    --bucket "$BUCKET_NAME" \
    --key "$S3_KEY" \
    --content-type "$FILE_TYPE" \
    --region "$REGION" \
    --output json 2>&1)

if [ $? -ne 0 ]; then
    echo "Error initiating multipart upload:"
    echo "$INITIATE_OUTPUT"
    exit 1
fi

UPLOAD_ID=$(echo "$INITIATE_OUTPUT" | jq -r '.UploadId')
echo "  Upload ID: $UPLOAD_ID"

# Generate presigned URLs for all parts
echo "Step 3: Generating presigned URLs for $TOTAL_PARTS parts..."

# Check for Docker with Python 3.12 - use container for presigned URL generation
USE_DOCKER=false
PYTHON_SCRIPT="generate-multipart-presigned-url.py"
DOCKER_HELPER="$SCRIPT_DIR/run-python-container.sh"

# Check if Docker is both installed AND running
if command -v docker &>/dev/null && [ -f "$DOCKER_HELPER" ]; then
    # Test if Docker daemon is actually running (with timeout to avoid hanging)
    if command -v timeout &>/dev/null; then
        if timeout 2 docker info &>/dev/null 2>&1; then
            USE_DOCKER=true
        fi
    else
        # Without timeout, use a quick check that won't hang
        if docker ps &>/dev/null 2>&1; then
            USE_DOCKER=true
        fi
    fi
    if [ "$USE_DOCKER" = false ]; then
        echo "  Note: Docker is not available. Using AWS CLI for presigned URLs..."
    fi
fi

if [ "$USE_DOCKER" = true ]; then
    echo "  Using Docker container (Python 3.12) to generate presigned URLs..."
else
    echo "  Using AWS CLI to generate presigned URLs..."
fi

declare -a PRESIGNED_URLS
declare -a PART_NUMBERS

for ((PART_NUMBER=1; PART_NUMBER<=TOTAL_PARTS; PART_NUMBER++)); do
    echo "  Generating URL for part $PART_NUMBER/$TOTAL_PARTS..."
    
    if [ "$USE_DOCKER" = true ]; then
        # Use Docker container with Python 3.12/boto3 for reliable presigned URL generation
        # Add timeout to prevent hanging
        if command -v timeout &>/dev/null; then
            PRESIGNED_URL=$(timeout 30 "$DOCKER_HELPER" "$PYTHON_SCRIPT" \
                --bucket "$BUCKET_NAME" \
                --key "$S3_KEY" \
                --upload-id "$UPLOAD_ID" \
                --part-number "$PART_NUMBER" \
                --region "$REGION" \
                --expires-in ${MULTIPART_EXPIRATION:-14400} 2>&1)
            PRESIGN_EXIT_CODE=$?
            if [ $PRESIGN_EXIT_CODE -eq 124 ]; then
                echo "Error: Presigned URL generation timed out after 30 seconds"
                PRESIGNED_URL="Error: Timeout"
            fi
        else
            PRESIGNED_URL=$("$DOCKER_HELPER" "$PYTHON_SCRIPT" \
                --bucket "$BUCKET_NAME" \
                --key "$S3_KEY" \
                --upload-id "$UPLOAD_ID" \
                --part-number "$PART_NUMBER" \
                --region "$REGION" \
                --expires-in ${MULTIPART_EXPIRATION:-14400} 2>&1)
            PRESIGN_EXIT_CODE=$?
        fi
    else
        # Fallback to AWS CLI
        PRESIGNED_URL=$(aws s3api presign \
            --bucket "$BUCKET_NAME" \
            --key "$S3_KEY" \
            --expires-in ${MULTIPART_EXPIRATION:-14400} \
            --region "$REGION" \
            --operation upload-part \
            --upload-id "$UPLOAD_ID" \
            --part-number "$PART_NUMBER" 2>&1)
        
        PRESIGN_EXIT_CODE=$?
    fi
    
    # Check for errors
    if [ $PRESIGN_EXIT_CODE -ne 0 ] || [[ "$PRESIGNED_URL" =~ ^[Ee]rror ]] || [[ "$PRESIGNED_URL" =~ ^usage: ]]; then
        echo "Error generating presigned URL for part $PART_NUMBER:"
        echo "$PRESIGNED_URL"
        # Abort upload
        aws s3api abort-multipart-upload \
            --bucket "$BUCKET_NAME" \
            --key "$S3_KEY" \
            --upload-id "$UPLOAD_ID" \
            --region "$REGION" 2>&1 >/dev/null
        
        if [ "$USE_DOCKER" = false ]; then
            echo ""
            echo "Tip: Use Docker for better presigned URL generation:"
            echo "  Install Docker and run: docker build -t s3uploader-python:latest -f test-uploads/Dockerfile test-uploads/"
        fi
        exit 1
    fi
    
    # Clean up the URL - extract just the URL, handling any extra output
    PRESIGNED_URL=$(echo "$PRESIGNED_URL" | grep -oE 'https://[^[:space:]]+' | head -1)
    if [ -z "$PRESIGNED_URL" ]; then
        # If grep didn't work, try simpler extraction
        PRESIGNED_URL=$(echo "$PRESIGNED_URL" | head -1 | tr -d '"' | tr -d "'" | tr -d '\n' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi
    
    # Validate URL
    if [[ ! "$PRESIGNED_URL" =~ ^https:// ]]; then
        echo "Error: Generated URL doesn't look valid for part $PART_NUMBER: $PRESIGNED_URL"
        # Abort upload
        aws s3api abort-multipart-upload \
            --bucket "$BUCKET_NAME" \
            --key "$S3_KEY" \
            --upload-id "$UPLOAD_ID" \
            --region "$REGION" 2>&1 >/dev/null
        exit 1
    fi
    
    # Print the presigned URL for this part
    echo "    Part $PART_NUMBER presigned URL: $PRESIGNED_URL"
    
    PRESIGNED_URLS[$PART_NUMBER]=$PRESIGNED_URL
    PART_NUMBERS[$PART_NUMBER]=$PART_NUMBER
done

echo "  ✓ All presigned URLs generated"

# Create temp directory for parts
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR; [ -n '$UPLOAD_ID' ] && aws s3api abort-multipart-upload --bucket $BUCKET_NAME --key $S3_KEY --upload-id $UPLOAD_ID --region $REGION 2>/dev/null || true" EXIT

# Upload parts
echo "Step 4: Uploading parts..."
declare -a ETAGS

for ((PART_NUMBER=1; PART_NUMBER<=TOTAL_PARTS; PART_NUMBER++)); do
    echo "  Uploading part $PART_NUMBER/$TOTAL_PARTS..."
    
    # Calculate byte range
    START_BYTE=$(( ($PART_NUMBER - 1) * $PART_SIZE ))
    END_BYTE=$(( $START_BYTE + $PART_SIZE - 1 ))
    if [ $END_BYTE -ge $FILE_SIZE ]; then
        END_BYTE=$(( $FILE_SIZE - 1 ))
    fi
    
    PART_SIZE_BYTES=$(( $END_BYTE - $START_BYTE + 1 ))
    
    # Extract part from file
    PART_FILE="$TEMP_DIR/part_${PART_NUMBER}.tmp"
    dd if="$FILE_PATH" of="$PART_FILE" bs=1 skip=$START_BYTE count=$PART_SIZE_BYTES 2>/dev/null
    
    # Upload part using presigned URL
    # Note: For multipart uploads, we MUST use presigned URLs (required by S3 multipart API)
    # The presigned URL is already SigV4 signed by AWS, so we use curl to upload it
    # Using curl preserves the presigned URL signature exactly as generated
    RESPONSE=$(curl -T "$PART_FILE" \
        --url "${PRESIGNED_URLS[$PART_NUMBER]}" \
        --silent \
        --show-error \
        -w "\nHTTP_CODE:%{http_code}" \
        -D "$TEMP_DIR/headers_${PART_NUMBER}.txt" 2>&1)
    
    HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d':' -f2)
    ETAG=$(grep -i "etag:" "$TEMP_DIR/headers_${PART_NUMBER}.txt" | cut -d' ' -f2 | tr -d '\r' | tr -d '"')
    
    if [ "$HTTP_CODE" == "200" ] && [ -n "$ETAG" ]; then
        ETAGS[$PART_NUMBER]="$ETAG"
        echo "    ✓ Part $PART_NUMBER uploaded (ETag: ${ETAG:0:20}...)"
        rm -f "$PART_FILE"
    else
        echo "    ✗ Part $PART_NUMBER upload failed (HTTP: $HTTP_CODE)"
        echo "$RESPONSE"
        exit 1
    fi
done

# Build parts JSON for completion
echo "Step 5: Building parts manifest..."
PARTS_JSON="{\"Parts\":["
for ((PART_NUMBER=1; PART_NUMBER<=TOTAL_PARTS; PART_NUMBER++)); do
    if [ $PART_NUMBER -gt 1 ]; then
        PARTS_JSON+=","
    fi
    PARTS_JSON+="{\"PartNumber\":$PART_NUMBER,\"ETag\":\"${ETAGS[$PART_NUMBER]}\"}"
done
PARTS_JSON+="]}"

echo "  Parts manifest built for $TOTAL_PARTS parts"

# Complete multipart upload
echo "Step 6: Completing multipart upload..."
echo "  Sending completion request..."

# Create a temporary file for the multipart upload JSON to avoid command line length issues
MULTIPART_FILE=$(mktemp)
echo "$PARTS_JSON" > "$MULTIPART_FILE"

# Complete the multipart upload
COMPLETE_OUTPUT=$(aws s3api complete-multipart-upload \
    --bucket "$BUCKET_NAME" \
    --key "$S3_KEY" \
    --upload-id "$UPLOAD_ID" \
    --multipart-upload "file://$MULTIPART_FILE" \
    --region "$REGION" \
    --output json 2>&1)

COMPLETE_EXIT_CODE=$?
rm -f "$MULTIPART_FILE"

if [ $COMPLETE_EXIT_CODE -eq 0 ]; then
    echo "✓ Multipart upload completed successfully!"
    if command -v jq &>/dev/null; then
        LOCATION=$(echo "$COMPLETE_OUTPUT" | jq -r '.Location // empty')
        ETAG=$(echo "$COMPLETE_OUTPUT" | jq -r '.ETag // empty')
        if [ -n "$LOCATION" ] && [ "$LOCATION" != "null" ]; then
            echo "  Location: $LOCATION"
        fi
        if [ -n "$ETAG" ] && [ "$ETAG" != "null" ]; then
            echo "  ETag: $ETAG"
        fi
    fi
    echo "  File: s3://$BUCKET_NAME/$S3_KEY"
    echo "  URL: https://$BUCKET_NAME.s3.$REGION.amazonaws.com/$S3_KEY"
elif [ $COMPLETE_EXIT_CODE -eq 124 ]; then
    echo "✗ Completion request timed out after 30 seconds"
    echo "  Upload ID: $UPLOAD_ID"
    echo "  You may need to complete it manually or check network connectivity"
    echo "$COMPLETE_OUTPUT"
    exit 1
else
    echo "✗ Failed to complete multipart upload:"
    echo "$COMPLETE_OUTPUT"
    exit 1
fi

# Cleanup
rm -rf "$TEMP_DIR"
trap - EXIT

