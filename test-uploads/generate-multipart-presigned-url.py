#!/usr/bin/env python3
"""
Generate a presigned URL for S3 multipart upload part using boto3.
This handles temporary credentials (session tokens) correctly.
"""

import sys
import os
import boto3
import argparse
from botocore.exceptions import ClientError

def generate_presigned_url(bucket, key, upload_id, part_number, region, expires_in=14400):
    """Generate a presigned URL for S3 multipart upload part."""
    try:
        # Create S3 client with credentials from environment
        s3_client = boto3.client('s3', region_name=region)
        
        # Generate presigned URL for upload_part operation
        url = s3_client.generate_presigned_url(
            'upload_part',
            Params={
                'Bucket': bucket,
                'Key': key,
                'UploadId': upload_id,
                'PartNumber': part_number
            },
            ExpiresIn=expires_in
        )
        
        return url
    except ClientError as e:
        print(f"Error generating presigned URL: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Generate presigned URL for S3 multipart upload part')
    parser.add_argument('--bucket', required=True, help='S3 bucket name')
    parser.add_argument('--key', required=True, help='S3 object key')
    parser.add_argument('--upload-id', required=True, help='Multipart upload ID')
    parser.add_argument('--part-number', type=int, required=True, help='Part number')
    parser.add_argument('--region', required=True, help='AWS region')
    parser.add_argument('--expires-in', type=int, default=14400, help='URL expiration in seconds (default: 14400)')
    
    args = parser.parse_args()
    
    url = generate_presigned_url(
        args.bucket,
        args.key,
        args.upload_id,
        args.part_number,
        args.region,
        args.expires_in
    )
    print(url)

