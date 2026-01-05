#!/bin/bash
# AWS Signature Version 4 (SigV4) signing helper
# This generates the Authorization header for AWS S3 requests

set -e

# Usage: sigv4_sign.sh <method> <bucket> <key> <region> <access_key> <secret_key> [session_token]

METHOD=${1:-PUT}
BUCKET=$2
KEY=$3
REGION=${4:-us-east-1}
ACCESS_KEY=$5
SECRET_KEY=$6
SESSION_TOKEN=$7

if [ $# -lt 6 ]; then
    echo "Usage: $0 <method> <bucket> <key> <region> <access_key> <secret_key> [session_token]"
    echo "Example: $0 PUT mybucket mykey us-east-1 AKIAIOSFODNN7EXAMPLE wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    exit 1
fi

# Get current time
NOW=$(date -u +"%Y%m%dT%H%M%SZ")
DATE_STAMP=$(echo "$NOW" | cut -c1-8)

# Service name
SERVICE="s3"
ENDPOINT="s3.${REGION}.amazonaws.com"

# Step 1: Create canonical request
CANONICAL_URI="/${KEY}"
CANONICAL_QUERYSTRING=""

# For PUT, we typically use UNSIGNED-PAYLOAD for presigned URLs
# For manual signing, we'd calculate the payload hash
PAYLOAD_HASH="UNSIGNED-PAYLOAD"

CANONICAL_HEADERS="host:${BUCKET}.${ENDPOINT}
x-amz-date:${NOW}"
SIGNED_HEADERS="host;x-amz-date"

# Add session token if provided
if [ -n "$SESSION_TOKEN" ]; then
    CANONICAL_HEADERS="${CANONICAL_HEADERS}
x-amz-security-token:${SESSION_TOKEN}"
    SIGNED_HEADERS="${SIGNED_HEADERS};x-amz-security-token"
fi

CANONICAL_HEADERS="${CANONICAL_HEADERS}
"

CANONICAL_REQUEST="${METHOD}
${CANONICAL_URI}
${CANONICAL_QUERYSTRING}
${CANONICAL_HEADERS}
${SIGNED_HEADERS}
${PAYLOAD_HASH}"

# Step 2: Create string to sign
ALGORITHM="AWS4-HMAC-SHA256"
CREDENTIAL_SCOPE="${DATE_STAMP}/${REGION}/${SERVICE}/aws4_request"

CANONICAL_REQUEST_HASH=$(echo -n "$CANONICAL_REQUEST" | openssl dgst -sha256 | cut -d' ' -f2)

STRING_TO_SIGN="${ALGORITHM}
${NOW}
${CREDENTIAL_SCOPE}
${CANONICAL_REQUEST_HASH}"

# Step 3: Calculate signature
kSecret="AWS4${SECRET_KEY}"
kDate=$(echo -n "$DATE_STAMP" | openssl dgst -sha256 -mac HMAC -macopt "key:${kSecret}" | cut -d' ' -f2 | sed 's/^\(.*\)$/echo -n \1 | xxd -r -p | openssl dgst -sha256 -mac HMAC -macopt "hexkey:"/e')
kRegion=$(echo -n "$REGION" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${kDate}" | cut -d' ' -f2 | sed 's/^\(.*\)$/echo -n \1 | xxd -r -p | openssl dgst -sha256 -mac HMAC -macopt "hexkey:"/e')
kService=$(echo -n "$SERVICE" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${kRegion}" | cut -d' ' -f2 | sed 's/^\(.*\)$/echo -n \1 | xxd -r -p | openssl dgst -sha256 -mac HMAC -macopt "hexkey:"/e')
kSigning=$(echo -n "aws4_request" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${kService}" | cut -d' ' -f2 | sed 's/^\(.*\)$/echo -n \1 | xxd -r -p | openssl dgst -sha256 -mac HMAC -macopt "hexkey:"/e')

SIGNATURE=$(echo -n "$STRING_TO_SIGN" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${kSigning}" | cut -d' ' -f2)

# Step 4: Create Authorization header
AUTHORIZATION_HEADER="${ALGORITHM} Credential=${ACCESS_KEY}/${CREDENTIAL_SCOPE}, SignedHeaders=${SIGNED_HEADERS}, Signature=${SIGNATURE}"

# Output the headers
echo "Authorization: ${AUTHORIZATION_HEADER}"
echo "x-amz-date: ${NOW}"
if [ -n "$SESSION_TOKEN" ]; then
    echo "x-amz-security-token: ${SESSION_TOKEN}"
fi

