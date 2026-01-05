# AWS Signature Version 4 (SigV4) Signing Guide

## Overview

AWS Signature Version 4 (SigV4) is the signing algorithm used by AWS for authenticating API requests. When you use presigned URLs, AWS generates them using SigV4. This guide explains different approaches to use SigV4 directly.

## Approaches to SigV4 Signing

### Option 1: AWS CLI (Recommended - Handles SigV4 Automatically)

The AWS CLI automatically signs all requests using SigV4. This is the easiest approach:

```bash
# Direct upload (automatically SigV4 signed)
aws s3 cp file.txt s3://bucket/key.txt --region us-east-1

# Generate presigned URL (also uses SigV4)
aws s3 presign s3://bucket/key.txt --expires-in 3600
```

**Advantages:**
- Automatic SigV4 signing
- Handles session tokens correctly
- Works with temporary credentials
- No additional code needed

### Option 2: awscurl (Curl Wrapper with SigV4)

`awscurl` is a tool that wraps curl and automatically adds SigV4 signatures.

**Installation:**
```bash
pip install awscurl
```

**Usage:**
```bash
# Set AWS credentials
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...  # For temporary credentials

# Upload file
awscurl --service s3 \
    --region us-east-1 \
    -X PUT \
    --data-binary "@file.txt" \
    https://bucket.s3.us-east-1.amazonaws.com/key.txt
```

**Advantages:**
- Works like curl but with automatic SigV4 signing
- Handles all AWS services
- Good for testing and scripting

### Option 3: Python with requests-aws4auth

Use Python library that handles SigV4 signing:

```python
import requests
from requests_aws4auth import AWS4Auth

# Credentials
access_key = 'AKIAIOSFODNN7EXAMPLE'
secret_key = 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
session_token = '...'  # Optional for temporary credentials
region = 'us-east-1'

# Create auth object
auth = AWS4Auth(access_key, secret_key, region, 's3', session_token=session_token)

# Upload file
url = f'https://bucket.s3.{region}.amazonaws.com/key.txt'
with open('file.txt', 'rb') as f:
    response = requests.put(url, data=f, auth=auth)

print(response.status_code)
```

### Option 4: Node.js with aws4

```bash
npm install aws4
```

```javascript
const https = require('https');
const aws4 = require('aws4');
const fs = require('fs');

const opts = {
    host: 'bucket.s3.us-east-1.amazonaws.com',
    path: '/key.txt',
    method: 'PUT',
    service: 's3',
    region: 'us-east-1'
};

aws4.sign(opts, {
    accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
    secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
    sessionToken: '...'  // Optional
});

const req = https.request(opts, (res) => {
    console.log('Status:', res.statusCode);
});

fs.createReadStream('file.txt').pipe(req);
```

### Option 5: Manual SigV4 Implementation (Advanced)

Manual SigV4 signing is complex and error-prone. It requires:

1. **Canonical Request:**
   - HTTP method
   - Canonical URI
   - Canonical query string
   - Canonical headers
   - Signed headers
   - Payload hash (UNSIGNED-PAYLOAD or SHA256)

2. **String to Sign:**
   - Algorithm (AWS4-HMAC-SHA256)
   - Request date/time
   - Credential scope
   - Hashed canonical request

3. **Signature Calculation:**
   - kSecret = "AWS4" + secret_key
   - kDate = HMAC-SHA256(kSecret, date_stamp)
   - kRegion = HMAC-SHA256(kDate, region)
   - kService = HMAC-SHA256(kRegion, service)
   - kSigning = HMAC-SHA256(kService, "aws4_request")
   - signature = HMAC-SHA256(kSigning, string_to_sign)

4. **Authorization Header:**
   ```
   Authorization: AWS4-HMAC-SHA256 \
     Credential=access_key/date/region/service/aws4_request, \
     SignedHeaders=host;x-amz-date, \
     Signature=signature
   ```

**Why Manual is Not Recommended:**
- Very complex to implement correctly
- Easy to make mistakes
- Edge cases (multipart uploads, special characters, etc.)
- Better to use existing libraries

## Current Implementation

The current scripts use **presigned URLs** which are already signed with SigV4 by AWS. The presigning happens on the server side (via boto3 in Docker or AWS CLI), and the URL contains all the signature information in query parameters.

**When to use each approach:**

| Approach | Use Case | Complexity |
|----------|----------|------------|
| AWS CLI | Direct uploads, simple operations | Easy |
| Presigned URLs | Client-side uploads, web apps | Easy |
| awscurl | Scripting with curl-like interface | Medium |
| Python requests-aws4auth | Python applications | Medium |
| Manual SigV4 | Custom implementations, learning | Hard |

## Recommendations

1. **For your current use case (bash scripts with temporary credentials):**
   - ✅ Keep using presigned URLs (current approach)
   - ✅ Or use AWS CLI directly: `aws s3 cp`
   - Consider `awscurl` if you need more curl-like control

2. **If you want to avoid presigned URLs:**
   - Use `aws s3 cp` directly (handles SigV4 automatically)
   - Or use `awscurl` for curl-like interface with SigV4

3. **If you need manual control:**
   - Use Python with `requests-aws4auth` or boto3
   - Use Node.js with `aws4` package
   - Avoid manual bash implementation (too error-prone)

## Example: Using awscurl

Install and use:

```bash
# Install
pip install awscurl

# Use in scripts
source ./assume-role.sh  # Sets AWS_* environment variables

awscurl --service s3 \
    --region us-east-1 \
    -X PUT \
    --data-binary "@file.txt" \
    -H "Content-Type: text/plain" \
    https://bucket.s3.us-east-1.amazonaws.com/key.txt
```

This automatically handles:
- SigV4 signing
- Session tokens
- Headers
- All AWS signature requirements

## Resources

- [AWS Signature Version 4 Signing Process](https://docs.aws.amazon.com/general/latest/gr/sigv4_signing.html)
- [Signing AWS API Requests](https://docs.aws.amazon.com/general/latest/gr/signing_aws_api_requests.html)
- [S3 Request Authentication](https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-authenticating-requests.html)
- [awscurl GitHub](https://github.com/okigan/awscurl)

