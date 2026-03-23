# =============================================================================
# IAM MODULE — VARIABLES
# =============================================================================

variable "app_name" {
  description = "Application name prefix"
  type        = string
}

variable "environment" {
  description = "Environment name — dev or prod"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID — used to build ECR ARNs"
  type        = string
}

variable "s3_media_bucket_arn" {
  description = "ARN of the S3 media bucket ECS tasks need access to"
  type        = string
}
