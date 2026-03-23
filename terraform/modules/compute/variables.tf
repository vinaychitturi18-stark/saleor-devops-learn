# =============================================================================
# COMPUTE MODULE — VARIABLES
# =============================================================================

variable "app_name" {
  description = "Application name prefix"
  type        = string
}

variable "environment" {
  description = "Environment name — dev or prod"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID — used to build ECR image URLs"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs where ECS tasks will run"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ALB security group ID — ECS tasks accept traffic only from ALB"
  type        = string
}

variable "target_group_arns" {
  description = "Map of target group name → ARN from loadbalancer module"
  type        = map(string)
  # { "backend" = "arn:...", "dashboard" = "arn:...", "storefront" = "arn:..." }
}

variable "task_execution_role_arn" {
  description = "ECS task execution role ARN from IAM module"
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN from IAM module"
  type        = string
}

variable "secrets_manager_arn" {
  description = "ARN of the Secrets Manager secret containing all app secrets"
  type        = string
}

variable "s3_media_bucket" {
  description = "Name of the S3 media bucket"
  type        = string
}

variable "public_url" {
  description = "Public URL of the app. prod=https://learnwithvinay.in, dev=https://dev.learnwithvinay.in"
  type        = string
}

# CONCEPT: Variable — complex type (map of objects)
# This is the most powerful variable in the whole project.
# Instead of repeating ECS service code 5 times, we define all 5 services
# in this map and loop over them with for_each.
variable "services" {
  description = "Map of ECS service configurations"
  type = map(object({
    cpu              = number
    memory           = number
    command          = list(string)  # empty list = use Dockerfile CMD
    desired_count    = number
    target_group_key = string        # which target group to attach to ("backend", "dashboard", "storefront", or "" for no ALB)
    container_port   = number        # port the container listens on (0 = not attached to ALB)
  }))
}

variable "ecr_repository_urls" {
  description = "Map of ECR repo name → URL from storage module"
  type        = map(string)
}
