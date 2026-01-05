#!/bin/bash
# Create IAM Role and Policies for S3 Upload Testing
# This script creates the IAM role and policies needed for the upload test scenario
# Usage: ./create-iam-resources.sh [role-name] [bucket-name] [principal-arn]

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
fi

# Configuration with defaults
ROLE_NAME=${1:-"S3UploadRole"}
BUCKET_NAME=${2:-${BUCKET_NAME:-"my-upload-bucket"}}
PRINCIPAL_ARN=${3:-""}  # Optional: specific principal that can assume the role
REGION=${REGION:-"us-east-1"}

# Account ID detection
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [ -z "$ACCOUNT_ID" ]; then
    echo "Error: Could not determine AWS account ID. Please ensure AWS CLI is configured."
    exit 1
fi

echo "=========================================="
echo "Creating IAM Role for S3 Upload Test"
echo "=========================================="
echo "Role Name: $ROLE_NAME"
echo "Bucket Name: $BUCKET_NAME"
echo "Account ID: $ACCOUNT_ID"
echo "Region: $REGION"
if [ -n "$PRINCIPAL_ARN" ]; then
    echo "Principal ARN: $PRINCIPAL_ARN"
else
    echo "Principal: Account ${ACCOUNT_ID} (any user/role in this account)"
fi
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Step 1: Create Trust Policy
echo "Step 1: Creating trust policy..."
if [ -n "$PRINCIPAL_ARN" ]; then
    # Specific principal
    TRUST_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "$PRINCIPAL_ARN"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)
else
    # Any principal in the account
    TRUST_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${ACCOUNT_ID}:root"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "aws:PrincipalAccount": "${ACCOUNT_ID}"
                }
            }
        }
    ]
}
EOF
)
fi

# Step 2: Create IAM Role
echo "Step 2: Creating IAM Role..."
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    echo -e "${YELLOW}Role $ROLE_NAME already exists. Updating trust policy...${NC}"
    aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document "$TRUST_POLICY" > /dev/null
    echo -e "${GREEN}✓ Trust policy updated${NC}"
else
    aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST_POLICY" > /dev/null
    echo -e "${GREEN}✓ Role $ROLE_NAME created${NC}"
fi

# Step 3: Create IAM Policy for Role (S3 permissions)
echo "Step 3: Creating IAM policy for role (S3 permissions)..."
ROLE_POLICY_NAME="${ROLE_NAME}-S3Policy"
ROLE_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${ROLE_POLICY_NAME}"

ROLE_POLICY_DOC=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl",
                "s3:GetObject",
                "s3:CreateMultipartUpload",
                "s3:UploadPart",
                "s3:CompleteMultipartUpload",
                "s3:AbortMultipartUpload"
            ],
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/uploads/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": "arn:aws:s3:::${BUCKET_NAME}",
            "Condition": {
                "StringLike": {
                    "s3:prefix": "uploads/*"
                }
            }
        }
    ]
}
EOF
)

# Check if policy exists
if aws iam get-policy --policy-arn "$ROLE_POLICY_ARN" &>/dev/null; then
    echo -e "${YELLOW}Policy $ROLE_POLICY_NAME already exists. Updating...${NC}"
    
    # Get current default version
    CURRENT_VERSION=$(aws iam get-policy --policy-arn "$ROLE_POLICY_ARN" --query 'Policy.DefaultVersionId' --output text)
    
    # Create new policy version
    NEW_VERSION=$(aws iam create-policy-version \
        --policy-arn "$ROLE_POLICY_ARN" \
        --policy-document "$ROLE_POLICY_DOC" \
        --set-as-default --output json | jq -r '.PolicyVersion.VersionId')
    
    # Delete old version if it exists and is not the only one
    VERSION_COUNT=$(aws iam list-policy-versions --policy-arn "$ROLE_POLICY_ARN" --query 'length(Versions)' --output text)
    if [ "$VERSION_COUNT" -gt 1 ] && [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
        aws iam delete-policy-version --policy-arn "$ROLE_POLICY_ARN" --version-id "$CURRENT_VERSION" 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✓ Policy updated${NC}"
else
    # Create policy
    ROLE_POLICY_ARN=$(aws iam create-policy \
        --policy-name "$ROLE_POLICY_NAME" \
        --policy-document "$ROLE_POLICY_DOC" \
        --output json | jq -r '.Policy.Arn')
    echo -e "${GREEN}✓ Policy $ROLE_POLICY_NAME created${NC}"
fi

# Attach policy to role
echo "Step 4: Attaching policy to role..."
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$ROLE_POLICY_ARN" 2>/dev/null || \
    echo -e "${YELLOW}Policy already attached${NC}"
echo -e "${GREEN}✓ Policy attached to role${NC}"

# Step 5: Wait for role to be ready
echo "Step 5: Waiting for role to propagate..."
sleep 3

# Summary
echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo -e "${GREEN}✓ IAM Role: $ROLE_NAME${NC}"
echo -e "${GREEN}✓ Role ARN: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}${NC}"
echo -e "${GREEN}✓ S3 Bucket: $BUCKET_NAME${NC}"
echo -e "${GREEN}✓ Policy: $ROLE_POLICY_ARN${NC}"
echo ""
if [ -n "$PRINCIPAL_ARN" ]; then
    echo "Trust Policy allows: $PRINCIPAL_ARN"
else
    echo "Trust Policy allows: Any principal in account ${ACCOUNT_ID}"
fi
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Update config.sh with the role ARN:"
echo "   export ROLE_ARN=\"arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}\""
echo "   export BUCKET_NAME=\"$BUCKET_NAME\""
echo ""
echo "2. Ensure your AWS credentials have permission to assume this role:"
echo "   - If using a specific user: grant sts:AssumeRole permission"
echo "   - If using root account: you can assume the role directly"
echo ""
if [ -z "$PRINCIPAL_ARN" ]; then
    echo "3. To restrict access to a specific user, run:"
    echo "   ./create-iam-resources.sh $ROLE_NAME $BUCKET_NAME arn:aws:iam::${ACCOUNT_ID}:user/YOUR_USER_NAME"
    echo ""
fi
echo "4. Test the upload with: ./simple-upload-awscli.sh <file>"
echo ""
