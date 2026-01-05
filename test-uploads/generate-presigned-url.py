#!/usr/bin/env python3
"""
Generate a presigned PUT URL for S3 using boto3.
This handles temporary credentials (session tokens) correctly.
"""

import sys
import os
import boto3
import argparse
from botocore.exceptions import ClientError

def generate_presigned_url(bucket, key, region, expires_in=3600):
    """Generate a presigned PUT URL for S3."""
    try:
        # Create S3 client with credentials from environment
        # Force SigV4 (s3v4) signing for presigned URLs and use regional endpoint
        import botocore.config
        config = botocore.config.Config(
            signature_version='s3v4',  # Force SigV4 (required for all S3 buckets)
            connect_timeout=10,
            read_timeout=10,
            retries={'max_attempts': 2}
        )
        # Use regional endpoint instead of global endpoint
        endpoint_url = f'https://s3.{region}.amazonaws.com'
        s3_client = boto3.client('s3', region_name=region, endpoint_url=endpoint_url, config=config)
        
        # Generate presigned URL for PUT operation
        url = s3_client.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': bucket,
                'Key': key
            },
            ExpiresIn=expires_in
        )
        
        return url
    except ClientError as e:
        print(f"Error generating presigned URL: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Generate presigned PUT URL for S3')
    parser.add_argument('--bucket', required=True, help='S3 bucket name')
    parser.add_argument('--key', required=True, help='S3 object key')
    parser.add_argument('--region', required=True, help='AWS region')
    parser.add_argument('--expires-in', type=int, default=3600, help='URL expiration in seconds (default: 3600)')
    
    args = parser.parse_args()
    
    url = generate_presigned_url(args.bucket, args.key, args.region, args.expires_in)
    print(url)

