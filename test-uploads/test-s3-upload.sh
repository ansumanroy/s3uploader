#!/bin/bash
# test-s3-debug.sh

source ./assume-role.sh

echo "Testing S3 access..."
echo "Credentials:"
echo "  Access Key: ${AWS_ACCESS_KEY_ID:0:10}..."
echo "  Session Token: ${AWS_SESSION_TOKEN:0:20}..."

# Test 1: Direct AWS CLI upload
echo -e "\nTest 1: Direct AWS CLI upload"
echo "test123" > /tmp/test.txt
aws s3 cp /tmp/test.txt s3://$BUCKET_NAME/test-direct.txt 2>&1

# Test 2: Presigned URL generation
echo -e "\nTest 2: Generate presigned URL"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/run-python-container.sh" ] && command -v docker &>/dev/null; then
    URL=$("$SCRIPT_DIR/run-python-container.sh" generate-presigned-url.py \
        --bucket "$BUCKET_NAME" \
        --key "test-presigned.txt" \
        --region "$REGION")
else
    echo "Error: Docker not available or helper script missing"
    exit 1
fi
echo "URL generated: ${URL:0:100}..."

# Test 3: Upload via presigned URL with verbose output
echo -e "\nTest 3: Upload via presigned URL"
curl -v -X PUT --url "$URL" --data-binary @/tmp/test.txt 2>&1 | tee /tmp/curl-debug.txt