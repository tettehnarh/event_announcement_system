variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Environment suffix (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

variable "name_prefix" {
  description = "Resource name prefix"
  type        = string
  default     = "event-announce-"
}

variable "website_index_document" {
  description = "Index document for S3 website hosting"
  type        = string
  default     = "index.html"
}

variable "website_error_document" {
  description = "Error document for S3 website hosting"
  type        = string
  default     = "index.html"
}

