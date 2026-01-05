#!/bin/bash
# Assume IAM Role and get temporary credentials
# Usage: source ./assume-role.sh

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
elif [ -f "$SCRIPT_DIR/config.sh.example" ]; then
    echo "Warning: Using config.sh.example. Please create config.sh with your actual values."
    source "$SCRIPT_DIR/config.sh.example"
else
    echo "Error: config.sh not found. Please create it from config.sh.example"
    exit 1
fi

# Set user credentials for assuming role (if provided)
# If USER_ACCESS_KEY is not set, use default AWS CLI credentials
USE_DEFAULT_CREDS=false
if [ -n "$USER_ACCESS_KEY" ] && [ "$USER_ACCESS_KEY" != "YOUR_ACCESS_KEY" ]; then
    export AWS_ACCESS_KEY_ID=$USER_ACCESS_KEY
    export AWS_SECRET_ACCESS_KEY=$USER_SECRET_KEY
    export AWS_DEFAULT_REGION=${REGION:-us-east-1}
    echo "Using user credentials from config.sh"
else
    USE_DEFAULT_CREDS=true
    echo "Using default AWS CLI credentials (USER_ACCESS_KEY not set in config.sh)"
    export AWS_DEFAULT_REGION=${REGION:-us-east-1}
fi

# Generate unique session name
ROLE_SESSION_NAME="upload-session-$(date +%s)"

echo "Assuming role: $ROLE_ARN"
echo "Session name: $ROLE_SESSION_NAME"

# Assume the role
if [ "$USE_DEFAULT_CREDS" = true ]; then
    # Use default AWS CLI credentials (already in environment)
    ASSUME_ROLE_OUTPUT=$(aws sts assume-role \
        --role-arn "$ROLE_ARN" \
        --role-session-name "$ROLE_SESSION_NAME" \
        --duration-seconds ${SESSION_DURATION:-3600} \
        --output json 2>&1)
else
    # Use user credentials from config
    ASSUME_ROLE_OUTPUT=$(AWS_ACCESS_KEY_ID=$USER_ACCESS_KEY \
        AWS_SECRET_ACCESS_KEY=$USER_SECRET_KEY \
        AWS_DEFAULT_REGION=${REGION:-us-east-1} \
        aws sts assume-role \
        --role-arn "$ROLE_ARN" \
        --role-session-name "$ROLE_SESSION_NAME" \
        --duration-seconds ${SESSION_DURATION:-3600} \
        --output json 2>&1)
fi

if [ $? -ne 0 ]; then
    echo "Error assuming role:"
    echo "$ASSUME_ROLE_OUTPUT"
    exit 1
fi

# Extract temporary credentials
ROLE_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
ROLE_SECRET_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
ROLE_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')
EXPIRATION=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.Expiration')

# Validate credentials were received
if [ "$ROLE_ACCESS_KEY" == "null" ] || [ -z "$ROLE_ACCESS_KEY" ]; then
    echo "Error: Failed to assume role. Check your credentials and role ARN."
    exit 1
fi

# Export role credentials
export AWS_ACCESS_KEY_ID=$ROLE_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$ROLE_SECRET_KEY
export AWS_SESSION_TOKEN=$ROLE_SESSION_TOKEN
export AWS_DEFAULT_REGION=$REGION

echo "✓ Role assumed successfully"
echo "  Access Key ID: ${ROLE_ACCESS_KEY:0:20}..."
echo "  Session expires at: $EXPIRATION"
echo ""
echo "Credentials exported to environment. You can now use AWS CLI commands."
echo ""
echo "To use in current shell, run: source ./assume-role.sh"

