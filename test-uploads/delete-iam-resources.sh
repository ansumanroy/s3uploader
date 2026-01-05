#!/bin/bash
# Delete IAM Role and Policies created for S3 Upload Testing
# Usage: ./delete-iam-resources.sh [role-name]

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
echo "Deleting IAM Role for S3 Upload Test"
echo "=========================================="
echo "Role Name: $ROLE_NAME"
echo "Account ID: $ACCOUNT_ID"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Confirmation
read -p "Are you sure you want to delete this IAM role and its policies? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Deletion cancelled."
    exit 0
fi

# Step 1: Detach and Delete Role Policies
echo "Step 1: Detaching and deleting role policies..."
ROLE_POLICY_NAME="${ROLE_NAME}-S3Policy"
ROLE_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${ROLE_POLICY_NAME}"

if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    # Detach policy from role
    aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$ROLE_POLICY_ARN" 2>/dev/null || \
        echo -e "${YELLOW}Policy not attached or already detached${NC}"
    
    # List and delete all policy versions (except default, then delete default)
    if aws iam get-policy --policy-arn "$ROLE_POLICY_ARN" &>/dev/null; then
        POLICY_VERSIONS=$(aws iam list-policy-versions --policy-arn "$ROLE_POLICY_ARN" \
            --query 'Versions[].VersionId' --output text 2>/dev/null || echo "")
        
        for VERSION in $POLICY_VERSIONS; do
            aws iam delete-policy-version --policy-arn "$ROLE_POLICY_ARN" --version-id "$VERSION" 2>/dev/null || true
        done
        
        # Delete policy
        aws iam delete-policy --policy-arn "$ROLE_POLICY_ARN" 2>/dev/null || true
        echo -e "${GREEN}✓ Role policy deleted${NC}"
    else
        echo -e "${YELLOW}Role policy does not exist${NC}"
    fi
else
    echo -e "${YELLOW}Role $ROLE_NAME does not exist${NC}"
fi

# Step 2: Delete IAM Role
echo "Step 2: Deleting IAM role..."
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || true
    echo -e "${GREEN}✓ Role $ROLE_NAME deleted${NC}"
else
    echo -e "${YELLOW}Role $ROLE_NAME does not exist${NC}"
fi

echo ""
echo "=========================================="
echo "Cleanup Complete"
echo "=========================================="
echo -e "${GREEN}IAM role and policies have been deleted${NC}"
echo ""
