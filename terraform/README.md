# Terraform Infrastructure for S3 Multipart Upload

This Terraform configuration creates the AWS infrastructure needed for the S3 multipart upload application:

- **S3 Bucket**: For storing uploaded files
- **Lambda Function**: Generates presigned URLs for multipart uploads
- **API Gateway HTTP API**: Exposes the Lambda function via REST endpoints
- **IAM Roles & Policies**: Proper permissions for Lambda to access S3
- **CloudWatch Logs**: Logging for Lambda and API Gateway

## Prerequisites

1. **AWS Account**: You need an AWS account with appropriate permissions
2. **AWS CLI**: Install and configure AWS CLI with credentials
3. **Terraform**: Install Terraform (>= 1.0)
4. **Node.js**: For Lambda function (Node.js 18.x)

## Quick Start

1. **Configure AWS credentials**:
   ```bash
   aws configure
   ```

2. **Copy terraform.tfvars.example to terraform.tfvars**:
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```

3. **Edit terraform.tfvars** with your configuration:
   ```hcl
   aws_region = "us-east-1"
   project_name = "s3uploader"
   environment = "dev"
   s3_bucket_name = "my-upload-bucket"  # Optional: leave empty for auto-generation
   allowed_origins = "https://example.com"  # Or "*" for development
   ```

4. **Initialize Terraform**:
   ```bash
   terraform init
   ```

5. **Plan the deployment**:
   ```bash
   terraform plan
   ```

6. **Apply the configuration**:
   ```bash
   terraform apply
   ```

7. **Get the API Gateway URL**:
   ```bash
   terraform output api_gateway_url
   ```

## Configuration

### Variables

See `variables.tf` for all available variables. Key variables:

- `aws_region`: AWS region for resources (default: `us-east-1`)
- `project_name`: Project name for resource naming (default: `s3uploader`)
- `s3_bucket_name`: S3 bucket name (leave empty for auto-generation)
- `environment`: Environment name (dev, staging, prod)
- `lambda_timeout`: Lambda timeout in seconds (default: 30)
- `lambda_memory_size`: Lambda memory in MB (default: 256)
- `presigned_url_expiry`: Presigned URL expiry in seconds (default: 3600)
- `allowed_origins`: CORS allowed origins (default: `*`)

### Outputs

After applying, Terraform will output:

- `s3_bucket_name`: Name of the S3 bucket
- `api_gateway_url`: Base API Gateway URL
- `api_gateway_initiate_url`: Endpoint for initiating uploads
- `api_gateway_complete_url`: Endpoint for completing uploads
- `api_gateway_abort_url`: Endpoint for aborting uploads
- `lambda_function_name`: Name of the Lambda function

## API Endpoints

The API Gateway exposes the following endpoints:

### 1. Initiate Upload
```
POST /initiate-upload
```

**Request Body**:
```json
{
  "fileName": "large-file.zip",
  "fileSize": 2147483648,
  "fileType": "application/zip",
  "totalParts": 410
}
```

**Response**:
```json
{
  "uploadId": "abc123...",
  "bucket": "your-bucket",
  "key": "uploads/large-file.zip",
  "presignedUrls": [
    {
      "partNumber": 1,
      "url": "https://s3.amazonaws.com/..."
    },
    ...
  ]
}
```

### 2. Complete Upload
```
POST /complete-upload
```

**Request Body**:
```json
{
  "uploadId": "abc123...",
  "parts": [
    {
      "PartNumber": 1,
      "ETag": "etag1"
    },
    ...
  ]
}
```

### 3. Abort Upload
```
POST /abort-upload
```

**Request Body**:
```json
{
  "uploadId": "abc123..."
}
```

## Usage with Frontend

Update your frontend code (`uploader-presigned.js`) to use the API Gateway URL:

```javascript
const uploader = new S3MultipartUploaderPresigned({
    apiEndpoint: 'https://your-api-gateway-url.execute-api.us-east-1.amazonaws.com/dev/initiate-upload',
    chunkSize: 5 * 1024 * 1024,
    maxRetries: 3
});
```

## Infrastructure Details

### S3 Bucket
- Server-side encryption enabled (AES256)
- Public access blocked
- Versioning (optional, configurable)
- Lifecycle policy for incomplete multipart uploads (optional)

### Lambda Function
- Runtime: Node.js 18.x
- Handler: `lambda-function.handler`
- Timeout: 30 seconds (configurable)
- Memory: 256 MB (configurable)
- Environment variables:
  - `S3_BUCKET`: S3 bucket name
  - `PRESIGNED_URL_EXPIRY`: Presigned URL expiry time
  - `NODE_ENV`: Environment name

### API Gateway
- Type: HTTP API (v2)
- CORS enabled
- Auto-deploy enabled
- Access logging enabled

### IAM Permissions
Lambda has permissions for:
- `s3:CreateMultipartUpload`
- `s3:UploadPart`
- `s3:CompleteMultipartUpload`
- `s3:AbortMultipartUpload`
- `s3:PutObject`
- `s3:GetObject`
- `s3:ListBucket`
- CloudWatch Logs

## Troubleshooting

### Lambda Function Not Found
- Check that `lambda-function.js` exists in the terraform directory
- Verify the handler name matches the file name

### API Gateway Returns 502
- Check CloudWatch Logs for Lambda errors
- Verify Lambda permissions
- Check Lambda timeout settings

### CORS Issues
- Verify `allowed_origins` in terraform.tfvars
- Check API Gateway CORS configuration
- Ensure OPTIONS method is handled

### S3 Access Denied
- Verify IAM role has S3 permissions
- Check S3 bucket policy
- Verify bucket name is correct

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete the S3 bucket and all uploaded files!

## Cost Estimation

Approximate monthly costs (varies by usage):

- **S3 Storage**: $0.023 per GB
- **Lambda**: $0.20 per 1M requests
- **API Gateway**: $1.00 per 1M requests
- **CloudWatch Logs**: $0.50 per GB

For light usage (< 100GB storage, < 1M requests), expect ~$5-10/month.

## Security Best Practices

1. **Restrict CORS origins**: Don't use `*` in production
2. **Enable S3 bucket encryption**: Already enabled (AES256)
3. **Use IAM roles**: Already configured with least privilege
4. **Enable CloudWatch Logs**: Already configured
5. **Set presigned URL expiry**: Configurable via `presigned_url_expiry`
6. **Enable S3 versioning**: Optional, configurable
7. **Enable S3 lifecycle policies**: Optional, configurable
8. **Use AWS WAF**: Consider adding for production

## Monitoring

### CloudWatch Logs
- Lambda logs: `/aws/lambda/s3uploader-presigned-urls-{environment}`
- API Gateway logs: `/aws/apigateway/s3uploader-api-{environment}`

### CloudWatch Metrics
- Lambda invocations, errors, duration
- API Gateway requests, latency, errors
- S3 requests, storage

## Support

For issues or questions:
1. Check CloudWatch Logs
2. Verify Terraform outputs
3. Check AWS Console for resource status
4. Review IAM permissions

## License

MIT

