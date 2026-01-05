#!/bin/bash
# Multipart file upload to S3 using presigned URLs with curl (hybrid approach)
# Uses AWS CLI for presigned URL generation, curl for upload
# Usage: ./multipart-upload-curl.sh <file-path> [s3-key] [part-size-mb]

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
TOTAL_PARTS=$(( ($FILE_SIZE + $PART_SIZE - 1) / $PART_SIZE ))

echo "Step 2: File information"
echo "  File: $FILE_PATH"
echo "  Size: $(numfmt --to=iec-i --suffix=B $FILE_SIZE)"
echo "  Type: $FILE_TYPE"
echo "  S3 Key: s3://$BUCKET_NAME/$S3_KEY"
echo "  Part size: ${PART_SIZE_MB}MB"
echo "  Total parts: $TOTAL_PARTS"

# Check if multipart upload is needed
if [ $TOTAL_PARTS -eq 1 ]; then
    echo "Note: File is small enough for single upload. Consider using simple-upload-curl.sh"
fi

# Initiate multipart upload using AWS CLI
echo "Step 3: Initiating multipart upload (using AWS CLI)..."
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

# Generate presigned URLs for all parts using AWS CLI
echo "Step 4: Generating presigned URLs for $TOTAL_PARTS parts (using AWS CLI)..."
declare -a PRESIGNED_URLS
declare -a PART_NUMBERS

for ((PART_NUMBER=1; PART_NUMBER<=TOTAL_PARTS; PART_NUMBER++)); do
    echo "  Generating URL for part $PART_NUMBER/$TOTAL_PARTS..."
    
    # Use s3api presign with upload-part operation for multipart uploads
    PRESIGNED_URL=$(aws s3api presign \
        --bucket "$BUCKET_NAME" \
        --key "$S3_KEY" \
        --expires-in ${MULTIPART_EXPIRATION:-14400} \
        --region "$REGION" \
        --operation upload-part \
        --upload-id "$UPLOAD_ID" \
        --part-number "$PART_NUMBER" 2>&1)
    
    if [ $? -ne 0 ]; then
        echo "Error generating presigned URL for part $PART_NUMBER:"
        echo "$PRESIGNED_URL"
        # Abort upload
        aws s3api abort-multipart-upload \
            --bucket "$BUCKET_NAME" \
            --key "$S3_KEY" \
            --upload-id "$UPLOAD_ID" \
            --region "$REGION" 2>&1 >/dev/null
        exit 1
    fi
    
    # Clean up the URL - remove quotes, whitespace, newlines
    PRESIGNED_URL=$(echo "$PRESIGNED_URL" | tr -d '"' | tr -d "'" | tr -d '\n' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    PRESIGNED_URLS[$PART_NUMBER]=$PRESIGNED_URL
    PART_NUMBERS[$PART_NUMBER]=$PART_NUMBER
    echo "PRESIGNED URL IS:"
    echo $PRESIGNED_URL
done

echo "  ✓ All presigned URLs generated"

# Create temp directory for parts
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR; [ -n '$UPLOAD_ID' ] && aws s3api abort-multipart-upload --bucket $BUCKET_NAME --key $S3_KEY --upload-id $UPLOAD_ID --region $REGION 2>/dev/null || true" EXIT

# Upload parts using curl
echo "Step 5: Uploading parts (using curl)..."
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
    
    # Upload part using curl
    # For multipart upload parts (uploadPart), Content-Type is not required
    # The presigned URL signature doesn't include Content-Type for uploadPart operations
    RESPONSE=$(curl -X PUT \
        --url "${PRESIGNED_URLS[$PART_NUMBER]}" \
        --data-binary @"$PART_FILE" \
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
echo "Step 6: Building parts manifest..."
PARTS_JSON="["
for ((PART_NUMBER=1; PART_NUMBER<=TOTAL_PARTS; PART_NUMBER++)); do
    if [ $PART_NUMBER -gt 1 ]; then
        PARTS_JSON+=","
    fi
    PARTS_JSON+="{\"PartNumber\":$PART_NUMBER,\"ETag\":\"${ETAGS[$PART_NUMBER]}\"}"
done
PARTS_JSON+="]"

# Complete multipart upload using AWS CLI
echo "Step 7: Completing multipart upload (using AWS CLI)..."
COMPLETE_OUTPUT=$(aws s3api complete-multipart-upload \
    --bucket "$BUCKET_NAME" \
    --key "$S3_KEY" \
    --upload-id "$UPLOAD_ID" \
    --multipart-upload "$PARTS_JSON" \
    --region "$REGION" \
    --output json 2>&1)

if [ $? -eq 0 ]; then
    echo "✓ Multipart upload completed successfully!"
    LOCATION=$(echo "$COMPLETE_OUTPUT" | jq -r '.Location')
    ETAG=$(echo "$COMPLETE_OUTPUT" | jq -r '.ETag')
    echo "  Location: $LOCATION"
    echo "  ETag: $ETAG"
    echo "  File: s3://$BUCKET_NAME/$S3_KEY"
    echo "  URL: https://s3.$REGION.amazonaws.com/$BUCKET_NAME/$S3_KEY"
else
    echo "✗ Failed to complete multipart upload:"
    echo "$COMPLETE_OUTPUT"
    exit 1
fi

# Cleanup
rm -rf "$TEMP_DIR"
trap - EXIT

