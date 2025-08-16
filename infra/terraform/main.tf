locals {
  project_name = "${var.name_prefix}${var.env}"
}

# S3 bucket for data (events JSON)
resource "aws_s3_bucket" "data" {
  bucket = "${local.project_name}-data"
}

resource "aws_s3_bucket_ownership_controls" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Initial events file (optional creation via object resource)
resource "aws_s3_object" "events_json" {
  bucket       = aws_s3_bucket.data.id
  key          = "events/events.json"
  content      = jsonencode({ events = [] })
  content_type = "application/json"
}

# S3 bucket for website hosting
resource "aws_s3_bucket" "web" {
  bucket = "${local.project_name}-web"
}

resource "aws_s3_bucket_ownership_controls" "web" {
  bucket = aws_s3_bucket.web.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_public_access_block" "web_pab" {
  bucket                  = aws_s3_bucket.web.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront OAC and distribution for web bucket
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${local.project_name}-oac"
  description                       = "OAC for web bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_s3_bucket" "web_data" {
  bucket = aws_s3_bucket.web.bucket
}

resource "aws_cloudfront_distribution" "web" {
  enabled             = true
  default_root_object = var.website_index_document

  origin {
    domain_name              = data.aws_s3_bucket.web_data.bucket_regional_domain_name
    origin_id                = "web-s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "web-s3-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true

    forwarded_values {
      query_string = true
      headers      = ["Origin"]
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Bucket policy to allow CloudFront OAC to read web bucket
resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC",
        Effect = "Allow",
        Principal = {
          Service = "cloudfront.amazonaws.com"
        },
        Action   = ["s3:GetObject"],
        Resource = ["${aws_s3_bucket.web.arn}/*"],
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.web.arn
          }
        }
      }
    ]
  })
}

# SNS Topic for announcements
resource "aws_sns_topic" "announcements" {
  name = "${local.project_name}-announcements"
}

# IAM for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${local.project_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }
    ]
  })
}

resource "aws_iam_policy" "lambda_logging" {
  name = "${local.project_name}-lambda-logging"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "*" }
    ]
  })
}

resource "aws_iam_policy" "lambda_s3_sns" {
  name = "${local.project_name}-lambda-s3-sns"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "DataBucketReadWrite",
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:PutObject"],
        Resource = [
          "${aws_s3_bucket.data.arn}/events/*"
        ]
      },
      {
        Sid      = "SNSTopicAccess",
        Effect   = "Allow",
        Action   = ["sns:Publish", "sns:Subscribe"],
        Resource = [aws_sns_topic.announcements.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logging_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}

resource "aws_iam_role_policy_attachment" "lambda_s3_sns_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_s3_sns.arn
}

# Package placeholders for Lambda code (zips will be created later)

# Lambda functions
resource "aws_lambda_function" "get_events" {
  function_name = "${local.project_name}-get-events"
  role          = aws_iam_role.lambda_role.arn
  handler       = "app.handler"
  runtime       = "python3.12"
  filename      = var.lambda_zip_path_get_events
  timeout       = 10
  environment {
    variables = {
      DATA_BUCKET = aws_s3_bucket.data.bucket
      EVENTS_KEY  = "events/events.json"
      CORS_ORIGIN = aws_cloudfront_distribution.web.domain_name
    }
  }
}

resource "aws_lambda_function" "post_event" {
  function_name = "${local.project_name}-post-event"
  role          = aws_iam_role.lambda_role.arn
  handler       = "app.handler"
  runtime       = "python3.12"
  filename      = var.lambda_zip_path_post_event
  timeout       = 10
  environment {
    variables = {
      DATA_BUCKET   = aws_s3_bucket.data.bucket
      EVENTS_KEY    = "events/events.json"
      TOPIC_ARN     = aws_sns_topic.announcements.arn
      CORS_ORIGIN   = aws_cloudfront_distribution.web.domain_name
      EMAIL_SUBJECT = "Your Daily Newsletter"
      EMAIL_CONTENT = "This is your newsletter delivered"
    }
  }
}

resource "aws_lambda_function" "subscribe_email" {
  function_name = "${local.project_name}-subscribe-email"
  role          = aws_iam_role.lambda_role.arn
  handler       = "app.handler"
  runtime       = "python3.12"
  filename      = var.lambda_zip_path_subscribe
  timeout       = 10
  environment {
    variables = {
      TOPIC_ARN   = aws_sns_topic.announcements.arn
      CORS_ORIGIN = aws_cloudfront_distribution.web.domain_name
    }
  }
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "api" {
  name        = "${local.project_name}-api"
  description = "Event announcement API"
}

# Resources
resource "aws_api_gateway_resource" "events" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "events"
}

resource "aws_api_gateway_resource" "subscribe" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "subscribe"
}

# Methods and Integrations
# GET /events -> get_events Lambda
resource "aws_api_gateway_method" "get_events" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.events.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_events" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.events.id
  http_method             = aws_api_gateway_method.get_events.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_events.arn}/invocations"
}

# POST /events -> post_event Lambda
resource "aws_api_gateway_method" "post_event" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.events.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "post_event" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.events.id
  http_method             = aws_api_gateway_method.post_event.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.post_event.arn}/invocations"
}

# POST /subscribe -> subscribe_email Lambda
resource "aws_api_gateway_method" "subscribe" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.subscribe.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "subscribe" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.subscribe.id
  http_method             = aws_api_gateway_method.subscribe.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.subscribe_email.arn}/invocations"
}

# CORS enablement via OPTIONS methods for both resources
resource "aws_api_gateway_method" "events_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.events.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "events_options" {
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = aws_api_gateway_resource.events.id
  http_method       = aws_api_gateway_method.events_options.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "events_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.events_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "events_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.events_options.http_method
  status_code = aws_api_gateway_method_response.events_options.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'https://${aws_cloudfront_distribution.web.domain_name}'"
  }
}

resource "aws_api_gateway_method" "subscribe_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.subscribe.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "subscribe_options" {
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = aws_api_gateway_resource.subscribe.id
  http_method       = aws_api_gateway_method.subscribe_options.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "subscribe_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.subscribe.id
  http_method = aws_api_gateway_method.subscribe_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "subscribe_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.subscribe.id
  http_method = aws_api_gateway_method.subscribe_options.http_method
  status_code = aws_api_gateway_method_response.subscribe_options.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'",
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'https://${aws_cloudfront_distribution.web.domain_name}'"
  }
}

# Deployments and stages
resource "aws_api_gateway_deployment" "api" {
  depends_on = [
    aws_api_gateway_integration.get_events,
    aws_api_gateway_integration.post_event,
    aws_api_gateway_integration.subscribe,
    aws_api_gateway_integration.events_options,
    aws_api_gateway_integration.subscribe_options
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = var.env
}

# Permissions for API Gateway to invoke Lambdas
resource "aws_lambda_permission" "apigw_get_events" {
  statement_id  = "AllowAPIGatewayInvokeGetEvents"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_events.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/events"
}

resource "aws_lambda_permission" "apigw_post_event" {
  statement_id  = "AllowAPIGatewayInvokePostEvent"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.post_event.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/events"
}

resource "aws_lambda_permission" "apigw_subscribe" {
  statement_id  = "AllowAPIGatewayInvokeSubscribe"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.subscribe_email.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/subscribe"
}

# Outputs
output "web_bucket" {
  value = aws_s3_bucket.web.bucket
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.web.domain_name
}

output "api_invoke_url" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.aws_region}.amazonaws.com/${var.env}"
}

