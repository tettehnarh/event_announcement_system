output "web_bucket_name" {
  description = "S3 bucket for hosting web app"
  value       = aws_s3_bucket.web.bucket
}

output "cloudfront_domain_name" {
  description = "CloudFront domain for the web app"
  value       = aws_cloudfront_distribution.web.domain_name
}

output "api_base_url" {
  description = "Invoke URL base for API"
  value       = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.aws_region}.amazonaws.com/${var.env}"
}

output "data_bucket_name" {
  description = "S3 bucket for data (events)"
  value       = aws_s3_bucket.data.bucket
}

output "sns_topic_arn" {
  description = "SNS Topic ARN for announcements"
  value       = aws_sns_topic.announcements.arn
}

