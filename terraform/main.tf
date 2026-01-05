terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Generate random suffix for bucket name if not provided
resource "random_string" "bucket_suffix" {
  count   = var.s3_bucket_name == "" ? 1 : 0
  length  = 8
  special = false
  upper   = false
}

locals {
  bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-${var.environment}-${random_string.bucket_suffix[0].result}"
  lambda_name = "${var.project_name}-presigned-urls-${var.environment}"
  api_name    = "${var.project_name}-api-${var.environment}"
}

# S3 Bucket for uploads
resource "aws_s3_bucket" "upload_bucket" {
  bucket = local.bucket_name

  tags = merge(
    var.tags,
    {
      Name = local.bucket_name
    }
  )
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "upload_bucket_versioning" {
  bucket = aws_s3_bucket.upload_bucket.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

# S3 Bucket Server Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "upload_bucket_encryption" {
  bucket = aws_s3_bucket.upload_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "upload_bucket_pab" {
  bucket = aws_s3_bucket.upload_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Lifecycle Configuration (optional)
resource "aws_s3_bucket_lifecycle_configuration" "upload_bucket_lifecycle" {
  count  = var.enable_lifecycle ? 1 : 0
  bucket = aws_s3_bucket.upload_bucket.id

  rule {
    id     = "cleanup-incomplete-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${local.lambda_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for Lambda - S3 permissions
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "${local.lambda_name}-s3-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:CreateMultipartUpload",
          "s3:UploadPart",
          "s3:CompleteMultipartUpload",
          "s3:AbortMultipartUpload",
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.upload_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.upload_bucket.arn
        ]
      }
    ]
  })
}

# IAM Policy for Lambda - CloudWatch Logs
resource "aws_iam_role_policy" "lambda_logs_policy" {
  name = "${local.lambda_name}-logs-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Archive Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda-function.js"
  output_path = "${path.module}/lambda-function.zip"
}

# Lambda Function
resource "aws_lambda_function" "presigned_urls" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda-function.handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      S3_BUCKET             = aws_s3_bucket.upload_bucket.id
      PRESIGNED_URL_EXPIRY  = var.presigned_url_expiry
      NODE_ENV              = var.environment
    }
  }

  tags = merge(
    var.tags,
    {
      Name = local.lambda_name
    }
  )
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = 7

  tags = var.tags
}

# API Gateway REST API
resource "aws_apigatewayv2_api" "api" {
  name          = local.api_name
  protocol_type = "HTTP"
  description   = "API Gateway for S3 multipart upload presigned URLs"

  cors_configuration {
    allow_origins = split(",", var.allowed_origins)
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["content-type", "x-amz-date", "authorization", "x-api-key"]
    max_age       = 86400
  }

  tags = var.tags
}

# API Gateway Integration
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id = aws_apigatewayv2_api.api.id

  integration_uri    = aws_lambda_function.presigned_urls.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

# API Gateway Route - Initiate Upload
resource "aws_apigatewayv2_route" "initiate_route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /initiate-upload"

  target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# API Gateway Route - Complete Upload
resource "aws_apigatewayv2_route" "complete_route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /complete-upload"

  target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# API Gateway Route - Abort Upload
resource "aws_apigatewayv2_route" "abort_route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /abort-upload"

  target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Note: CORS is handled by API Gateway CORS configuration
# No need for explicit OPTIONS routes with HTTP API v2

# CloudWatch Log Group for API Gateway (must be created before stage)
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${local.api_name}"
  retention_in_days = 7

  tags = var.tags
}

# API Gateway Stage
resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = var.environment
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = var.tags
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.presigned_urls.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

