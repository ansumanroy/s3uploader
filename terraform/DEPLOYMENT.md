# Deployment Guide

This guide walks you through deploying the S3 multipart upload infrastructure using Terraform.

## Prerequisites

1. **AWS Account**: You need an AWS account with appropriate permissions
2. **AWS CLI**: Install and configure AWS CLI
   ```bash
   aws configure
   ```
3. **Terraform**: Install Terraform (>= 1.0)
   ```bash
   # macOS
   brew install terraform
   
   # Linux
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```
4. **Node.js**: For Lambda function (Node.js 18.x)

## Step-by-Step Deployment

### 1. Configure Variables

Copy the example terraform.tfvars file:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your configuration:

```hcl
aws_region = "us-east-1"
project_name = "s3uploader"
environment = "dev"
s3_bucket_name = ""  # Leave empty for auto-generation
allowed_origins = "*"  # Or specify your domain
presigned_url_expiry = 3600
```

### 2. Initialize Terraform

```bash
terraform init
```

This will download the required Terraform providers.

### 3. Plan the Deployment

```bash
terraform plan
```

Review the plan to see what resources will be created:
- S3 bucket
- Lambda function
- API Gateway HTTP API
- IAM roles and policies
- CloudWatch log groups

### 4. Apply the Configuration

```bash
terraform apply
```

Type `yes` when prompted to confirm the deployment.

### 5. Get the API Gateway URL

After deployment, get the API Gateway URL:

```bash
terraform output api_gateway_url
```

Or get all outputs:

```bash
terraform output
```

### 6. Update Frontend Configuration

Update your frontend code (`uploader-presigned.js`) with the API Gateway URL:

```javascript
const uploader = new S3MultipartUploaderPresigned({
    apiEndpoint: 'https://your-api-gateway-url.execute-api.us-east-1.amazonaws.com/dev/initiate-upload',
    chunkSize: 5 * 1024 * 1024,
    maxRetries: 3
});
```

## Testing the Deployment

### Test Initiate Upload

```bash
curl -X POST https://your-api-gateway-url.execute-api.us-east-1.amazonaws.com/dev/initiate-upload \
  -H "Content-Type: application/json" \
  -d '{
    "fileName": "test-file.zip",
    "fileSize": 10485760,
    "fileType": "application/zip",
    "totalParts": 2
  }'
```

Expected response:
```json
{
  "uploadId": "abc123...",
  "bucket": "s3uploader-dev-xxx",
  "key": "uploads/test-file.zip",
  "presignedUrls": [
    {
      "partNumber": 1,
      "url": "https://s3.amazonaws.com/..."
    },
    {
      "partNumber": 2,
      "url": "https://s3.amazonaws.com/..."
    }
  ]
}
```

### Test Complete Upload

```bash
curl -X POST https://your-api-gateway-url.execute-api.us-east-1.amazonaws.com/dev/complete-upload \
  -H "Content-Type: application/json" \
  -d '{
    "uploadId": "abc123...",
    "parts": [
      {
        "PartNumber": 1,
        "ETag": "etag1"
      },
      {
        "PartNumber": 2,
        "ETag": "etag2"
      }
    ]
  }'
```

## Monitoring

### CloudWatch Logs

View Lambda logs:
```bash
aws logs tail /aws/lambda/s3uploader-presigned-urls-dev --follow
```

View API Gateway logs:
```bash
aws logs tail /aws/apigateway/s3uploader-api-dev --follow
```

### CloudWatch Metrics

View Lambda metrics in AWS Console:
- Go to CloudWatch > Metrics > Lambda
- Select your Lambda function
- View invocations, errors, duration

View API Gateway metrics:
- Go to CloudWatch > Metrics > API Gateway
- Select your API
- View requests, latency, errors

## Troubleshooting

### Lambda Function Not Found

**Error**: `Error: Function not found`

**Solution**: 
1. Check Lambda function exists: `aws lambda get-function --function-name s3uploader-presigned-urls-dev`
2. Verify handler name matches: `lambda-function.handler`
3. Check Lambda function code is deployed

### API Gateway Returns 502

**Error**: `502 Bad Gateway`

**Solution**:
1. Check CloudWatch Logs for Lambda errors
2. Verify Lambda permissions
3. Check Lambda timeout settings
4. Verify API Gateway integration is correct

### CORS Issues

**Error**: `CORS policy: No 'Access-Control-Allow-Origin' header`

**Solution**:
1. Verify `allowed_origins` in terraform.tfvars
2. Check API Gateway CORS configuration
3. Ensure OPTIONS method is handled
4. Verify CORS headers in Lambda response

### S3 Access Denied

**Error**: `AccessDenied: Access Denied`

**Solution**:
1. Verify IAM role has S3 permissions
2. Check S3 bucket policy
3. Verify bucket name is correct
4. Check Lambda environment variables

## Updating the Deployment

### Update Lambda Function

1. Modify `lambda-function.js`
2. Run `terraform apply` to update the Lambda function

### Update Configuration

1. Modify `terraform.tfvars`
2. Run `terraform apply` to update resources

### Update API Gateway

1. Modify `main.tf` (routes, integrations, etc.)
2. Run `terraform apply` to update API Gateway

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete:
- S3 bucket and all uploaded files
- Lambda function
- API Gateway
- CloudWatch logs
- IAM roles and policies

## Cost Optimization

### Reduce Costs

1. **Enable S3 lifecycle policies**: Automatically delete old files
2. **Reduce CloudWatch log retention**: Default is 7 days
3. **Optimize Lambda memory**: Default is 256 MB
4. **Use S3 Intelligent-Tiering**: For infrequently accessed files
5. **Enable S3 versioning only if needed**: Increases storage costs

### Cost Monitoring

Monitor costs in AWS Cost Explorer:
- S3 storage costs
- Lambda invocation costs
- API Gateway request costs
- CloudWatch log storage costs

## Security Best Practices

1. **Restrict CORS origins**: Don't use `*` in production
2. **Enable S3 bucket encryption**: Already enabled (AES256)
3. **Use IAM roles**: Already configured with least privilege
4. **Enable CloudWatch Logs**: Already enabled
5. **Set presigned URL expiry**: Configurable via `presigned_url_expiry`
6. **Enable S3 versioning**: Optional, for audit trails
7. **Use AWS WAF**: Consider adding for production
8. **Enable API Gateway throttling**: Prevent abuse
9. **Use VPC for Lambda**: For enhanced security
10. **Enable AWS CloudTrail**: For audit logging

## Production Deployment

### Before Production

1. **Set environment to `prod`**: Update `terraform.tfvars`
2. **Restrict CORS origins**: Set specific domains
3. **Enable S3 versioning**: For audit trails
4. **Enable S3 lifecycle policies**: For cost optimization
5. **Increase Lambda timeout**: For large files
6. **Enable API Gateway throttling**: Prevent abuse
7. **Set up CloudWatch alarms**: For monitoring
8. **Enable AWS WAF**: For security
9. **Use custom domain**: For API Gateway
10. **Enable SSL/TLS**: Already enabled by default

### Production Checklist

- [ ] Environment set to `prod`
- [ ] CORS origins restricted
- [ ] S3 versioning enabled
- [ ] S3 lifecycle policies enabled
- [ ] Lambda timeout increased
- [ ] API Gateway throttling enabled
- [ ] CloudWatch alarms configured
- [ ] AWS WAF enabled
- [ ] Custom domain configured
- [ ] SSL/TLS enabled
- [ ] CloudTrail enabled
- [ ] Cost monitoring enabled
- [ ] Backup strategy defined
- [ ] Disaster recovery plan defined

## Support

For issues or questions:
1. Check CloudWatch Logs
2. Verify Terraform outputs
3. Check AWS Console for resource status
4. Review IAM permissions
5. Check AWS Service Health Dashboard

## License

MIT

