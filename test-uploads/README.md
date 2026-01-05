# Test Uploads - AWS CLI and cURL Scripts

This directory contains scripts for testing S3 uploads using presigned URLs with AWS CLI and curl.

## Use Case

A user with access key/secret key assumes an IAM role to generate presigned URLs for S3 uploads:

```
User Credentials → Assume Role → Role Credentials → Generate Presigned URLs → Upload to S3
```

**Why assume a role?**
- Security: User credentials have minimal permissions (only `sts:AssumeRole`)
- Least privilege: The assumed role has S3 permissions, not the user directly
- Audit trail: CloudTrail logs role assumption
- Temporary credentials: Assumed role provides temporary credentials

## Prerequisites

1. **AWS CLI** installed and configured
   ```bash
   aws --version
   # If not installed: https://aws.amazon.com/cli/
   ```

2. **jq** installed (for JSON parsing)
   ```bash
   jq --version
   # macOS: brew install jq
   # Linux: sudo apt-get install jq
   ```

3. **curl** installed (usually pre-installed)
   ```bash
   curl --version
   ```

4. **IAM Setup** (if not using `create-iam-resources.sh`):
   - IAM Role with trust policy allowing your principal to assume it
   - IAM Role with S3 permissions:
     - `s3:PutObject`
     - `s3:PutObjectAcl`
     - `s3:CreateMultipartUpload`
     - `s3:UploadPart`
     - `s3:CompleteMultipartUpload`
     - `s3:AbortMultipartUpload`
     - `s3:ListBucket` (for `uploads/*` prefix)
   - If using a user: user must have permission to assume the role (`sts:AssumeRole`)
   
   **Tip**: Use `./create-iam-resources.sh` to create the IAM role automatically!

## Quick Start

### Option 1: Create IAM Role Automatically (Recommended)

1. **Create IAM role**:
   ```bash
   ./create-iam-resources.sh S3UploadRole my-bucket
   ```
   
   This will create:
   - IAM Role with S3 permissions
   - Trust policy (allows any principal in your account to assume the role)
   - Role policy with S3 upload permissions
   
   **Note**: To restrict to a specific user, pass the user ARN as third parameter:
   ```bash
   ./create-iam-resources.sh S3UploadRole my-bucket arn:aws:iam::123456789012:user/my-user
   ```

2. **Update config.sh** with the role ARN from step 1:
   ```bash
   cp config.sh.example config.sh
   # Edit config.sh:
   # export ROLE_ARN="arn:aws:iam::123456789012:role/S3UploadRole"
   # export BUCKET_NAME="my-bucket"
   ```

3. **Ensure your AWS credentials can assume the role**:
   - If using root account: you can assume the role directly
   - If using a user: ensure the user has `sts:AssumeRole` permission for this role

4. **Test the upload**:
   ```bash
   ./simple-upload-awscli.sh ./myfile.txt uploads/myfile.txt
   ```

### Option 2: Manual IAM Setup

1. **Create IAM role manually** (using AWS Console or CLI):
   - Create role with trust policy allowing your principal
   - Attach policy with S3 permissions for `bucket-name/uploads/*`

2. **Copy and edit config.sh**:
   ```bash
   cp config.sh.example config.sh
   # Edit config.sh with your values
   ```

3. **Update configuration values**:
   ```bash
   # IAM Role to assume
   export ROLE_ARN="arn:aws:iam::123456789012:role/S3UploadRole"
   
   # S3 Configuration
   export BUCKET_NAME="my-upload-bucket"
   export REGION="ap-southeast-2"
   ```
   
   **Note**: If using a user, also set:
   ```bash
   export USER_ACCESS_KEY="YOUR_ACCESS_KEY"
   export USER_SECRET_KEY="YOUR_SECRET_KEY"
   ```

## Scripts

### IAM Management Scripts

### 1. create-iam-resources.sh
Creates IAM role and policies for testing uploads.

**Usage**:
```bash
chmod +x create-iam-resources.sh
./create-iam-resources.sh [role-name] [bucket-name] [principal-arn]
```

**Example**:
```bash
# Create role accessible by any principal in your account
./create-iam-resources.sh S3UploadRole my-bucket

# Create role accessible by specific user
./create-iam-resources.sh S3UploadRole my-bucket arn:aws:iam::123456789012:user/my-user

# Create role accessible by specific role
./create-iam-resources.sh S3UploadRole my-bucket arn:aws:iam::123456789012:role/another-role
```

**What it creates**:
- IAM Role with S3 permissions
- Trust policy (allows specified principal(s) to assume role)
- Role policy with S3 upload permissions

**Output**: Displays role ARN and configuration values to add to `config.sh`

### 2. delete-iam-resources.sh
Deletes IAM role and policies created by `create-iam-resources.sh`.

**Usage**:
```bash
chmod +x delete-iam-resources.sh
./delete-iam-resources.sh [role-name]
```

**Example**:
```bash
./delete-iam-resources.sh S3UploadRole
```

**Warning**: This will permanently delete the IAM role and policies.

### 3. list-iam-resources.sh
Lists IAM role and policies with their configuration.

**Usage**:
```bash
chmod +x list-iam-resources.sh
./list-iam-resources.sh [role-name]
```

**Example**:
```bash
./list-iam-resources.sh S3UploadRole
```

### Upload Scripts

### 4. assume-role.sh
Assumes an IAM role and exports temporary credentials to the environment.

**Usage**:
```bash
source ./assume-role.sh
```

**Output**:
- Exports `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`

### 5. simple-upload-awscli.sh
Simple file upload using AWS CLI for presigned URL generation and curl for upload.

**Usage**:
```bash
chmod +x simple-upload-awscli.sh
./simple-upload-awscli.sh <file-path> [s3-key]
```

**Example**:
```bash
./simple-upload-awscli.sh ./myfile.txt uploads/myfile.txt
```

**Features**:
- Assumes role automatically
- Generates presigned URL
- Uploads file using curl
- Shows upload progress

### 6. multipart-upload-awscli.sh
Multipart upload for large files using AWS CLI for presigned URL generation.

**Usage**:
```bash
chmod +x multipart-upload-awscli.sh
./multipart-upload-awscli.sh <file-path> [s3-key] [part-size-mb]
```

**Example**:
```bash
# Upload 2GB file with 50MB parts
./multipart-upload-awscli.sh ./large-file.mp4 uploads/video.mp4 50
```

**Features**:
- Assumes role automatically
- Initiates multipart upload
- Generates presigned URLs for all parts
- Uploads parts concurrently (sequential)
- Completes multipart upload
- Automatic cleanup on error

### 7. simple-upload-curl.sh
Simple file upload using curl (hybrid: AWS CLI for presigned URLs, curl for upload).

**Usage**:
```bash
chmod +x simple-upload-curl.sh
./simple-upload-curl.sh <file-path> [s3-key]
```

**Example**:
```bash
./simple-upload-curl.sh ./myfile.txt uploads/myfile.txt
```

### 8. multipart-upload-curl.sh
Multipart upload using curl (hybrid: AWS CLI for presigned URLs, curl for upload).

**Usage**:
```bash
chmod +x multipart-upload-curl.sh
./multipart-upload-curl.sh <file-path> [s3-key] [part-size-mb]
```

**Example**:
```bash
./multipart-upload-curl.sh ./large-file.mp4 uploads/video.mp4 50
```

## Examples

### Example 1: Complete Setup and Upload
```bash
# Step 1: Create IAM role
./create-iam-resources.sh S3UploadRole my-bucket

# Step 2: Update config.sh with role ARN from output
cp config.sh.example config.sh
# Edit config.sh:
# export ROLE_ARN="arn:aws:iam::123456789012:role/S3UploadRole"
# export BUCKET_NAME="my-bucket"

# Step 3: Upload a file
./simple-upload-awscli.sh ./myfile.txt uploads/myfile.txt
```

### Example 2: Upload Small File
```bash
# Make scripts executable
chmod +x *.sh

# Upload a text file
./simple-upload-awscli.sh ./document.txt uploads/document.txt
```

### Example 3: Upload Large File (2GB)
```bash
# Upload with 50MB parts (default)
./multipart-upload-awscli.sh ./large-video.mp4 uploads/video.mp4

# Upload with 100MB parts
./multipart-upload-awscli.sh ./large-video.mp4 uploads/video.mp4 100
```

### Example 4: List IAM Role
```bash
# List the created IAM role
./list-iam-resources.sh

# List specific role
./list-iam-resources.sh S3UploadRole
```

### Example 5: Cleanup IAM Resources
```bash
# Delete IAM role and policies
./delete-iam-resources.sh S3UploadRole
```

### Example 6: Assume Role Manually
```bash
# Assume role and export credentials
source ./assume-role.sh

# Now you can use AWS CLI commands directly
aws s3 ls s3://my-bucket/uploads/
```

## Part Size Recommendations

| File Size | Recommended Part Size | Number of Parts |
|-----------|----------------------|-----------------|
| < 100MB | Use simple upload | 1 |
| 100MB - 1GB | 10-50MB | 10-20 |
| 1GB - 5GB | 50-100MB | 10-100 |
| > 5GB | 100-500MB | 10-50 |

**Notes**:
- Minimum part size: 5MB
- Maximum part size: 5GB
- Maximum parts: 10,000

## Troubleshooting

### Error: "Failed to assume role"
- Check user credentials in `config.sh`
- Verify user has `sts:AssumeRole` permission
- Verify role ARN is correct
- Check IAM trust policy allows user to assume role

### Error: "Access Denied" when uploading
- Verify assumed role has S3 permissions
- Check bucket policy
- Verify presigned URL is not expired

### Error: "InvalidPart" during multipart upload
- Ensure part numbers are sequential (1, 2, 3, ...)
- Verify ETags are correct
- Check part size is at least 5MB

### Error: Presigned URL expired
- Increase `PRESIGNED_URL_EXPIRATION` in config.sh
- For large files, use 4 hours (14400 seconds)

## Security Best Practices

1. **Never commit credentials**: Keep `config.sh` in `.gitignore`
2. **Use IAM roles**: Don't give users direct S3 permissions
3. **Set expiration**: Use appropriate presigned URL expiration times
4. **Rotate credentials**: Regularly rotate access keys
5. **Monitor access**: Use CloudTrail to monitor role assumptions

## Limitations

### AWS CLI Scripts
- Requires AWS CLI installed
- Requires jq for JSON parsing
- Generates presigned URLs using AWS CLI

### cURL Scripts (Hybrid)
- Still uses AWS CLI for presigned URL generation
- Pure curl implementation would require manual AWS Signature V4 signing (complex)

### Pure cURL Implementation
For a pure curl implementation without AWS CLI, you would need to:
1. Sign STS AssumeRole request manually
2. Sign S3 CreateMultipartUpload request manually
3. Sign S3 Presign requests manually
4. This is complex and error-prone - not recommended

## IAM Policy Examples

### User Policy (Minimal)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::123456789012:role/S3UploadRole"
    }
  ]
}
```

### Role Trust Policy
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:user/upload-user"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### Role Permissions Policy
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:CreateMultipartUpload",
        "s3:UploadPart",
        "s3:CompleteMultipartUpload",
        "s3:AbortMultipartUpload"
      ],
      "Resource": "arn:aws:s3:::my-upload-bucket/uploads/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::my-upload-bucket"
    }
  ]
}
```

## License

MIT

