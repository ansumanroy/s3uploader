#!/bin/bash
# List IAM Role and Policies created for S3 Upload Testing
# Usage: ./list-iam-resources.sh [role-name]

set -e

# Configuration with defaults
ROLE_NAME=${1:-"S3UploadRole"}

# Account ID detection
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
if [ -z "$ACCOUNT_ID" ]; then
    echo "Error: Could not determine AWS account ID. Please ensure AWS CLI is configured."
    exit 1
fi

echo "=========================================="
echo "IAM Role for S3 Upload Test"
echo "=========================================="
echo "Role Name: $ROLE_NAME"
echo "Account ID: $ACCOUNT_ID"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check IAM Role
echo "IAM Role:"
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
    CREATED=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.CreateDate' --output text)
    echo -e "  ${GREEN}✓ Role exists${NC}"
    echo "  ARN: $ROLE_ARN"
    echo "  Created: $CREATED"
    
    # Show trust policy
    echo ""
    echo "  Trust Policy:"
    TRUST_POLICY=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.AssumeRolePolicyDocument' --output json)
    echo "$TRUST_POLICY" | jq '.' | sed 's/^/    /'
    
    # List attached policies
    echo ""
    echo "  Attached Policies:"
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    if [ -n "$ATTACHED_POLICIES" ]; then
        for POLICY_ARN in $ATTACHED_POLICIES; do
            POLICY_NAME=$(echo "$POLICY_ARN" | awk -F'/' '{print $NF}')
            echo "    - $POLICY_ARN"
            
            # Show policy document
            POLICY_VERSION=$(aws iam get-policy --policy-arn "$POLICY_ARN" --query 'Policy.DefaultVersionId' --output text 2>/dev/null)
            if [ -n "$POLICY_VERSION" ]; then
                echo "      Policy Document:"
                aws iam get-policy-version --policy-arn "$POLICY_ARN" --version-id "$POLICY_VERSION" \
                    --query 'PolicyVersion.Document' --output json | jq '.' | sed 's/^/        /'
            fi
        done
    else
        echo "    (None)"
    fi
else
    echo -e "  ${YELLOW}✗ Role does not exist${NC}"
    echo ""
    echo "Run ./create-iam-resources.sh to create the IAM role first."
fi

echo ""
echo "=========================================="
echo "Quick Reference"
echo "=========================================="
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
    
    echo "Add this to config.sh:"
    echo "  export ROLE_ARN=\"$ROLE_ARN\""
    echo ""
    echo "To use this role:"
    echo "1. Ensure your AWS credentials have permission to assume this role"
    echo "2. Update config.sh with the ROLE_ARN above"
    echo "3. Test with: ./simple-upload-awscli.sh <file>"
else
    echo "Run ./create-iam-resources.sh to create the IAM role first."
fi
echo ""

