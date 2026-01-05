output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.upload_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.upload_bucket.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.presigned_urls.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.presigned_urls.arn
}

output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = aws_apigatewayv2_stage.api_stage.invoke_url
}

output "api_gateway_initiate_url" {
  description = "API Gateway endpoint URL for initiate upload"
  value       = "${aws_apigatewayv2_stage.api_stage.invoke_url}/initiate-upload"
}

output "api_gateway_complete_url" {
  description = "API Gateway endpoint URL for complete upload"
  value       = "${aws_apigatewayv2_stage.api_stage.invoke_url}/complete-upload"
}

output "api_gateway_abort_url" {
  description = "API Gateway endpoint URL for abort upload"
  value       = "${aws_apigatewayv2_stage.api_stage.invoke_url}/abort-upload"
}

output "lambda_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda_role.arn
}

output "cloudwatch_log_group_lambda" {
  description = "CloudWatch Log Group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_api" {
  description = "CloudWatch Log Group for API Gateway"
  value       = aws_cloudwatch_log_group.api_gateway_logs.name
}

