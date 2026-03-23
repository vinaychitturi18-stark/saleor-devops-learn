# =============================================================================
# CONCEPT: Variables
# These are the inputs for the prod environment.
# Actual values live in terraform.tfvars (never committed to git for secrets)
# =============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Application name — used as prefix for all resource names"
  type        = string
  default     = "saleor"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
  default     = "249297038289"
}

# Networking
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs — one per AZ"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs — one per AZ"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

# Database
variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.small"
}

variable "db_allocated_storage" {
  description = "RDS storage in GB"
  type        = number
  default     = 20
}

# Domain
variable "domain_name" {
  description = "Root domain name"
  type        = string
  default     = "learnwithvinay.in"
}

variable "public_url" {
  description = "Full public URL of the app"
  type        = string
  default     = "https://learnwithvinay.in"
}

# ECS Services
# CONCEPT: Variable — complex type
# All 5 services defined here. Passed to compute module which loops with for_each.
variable "services" {
  description = "ECS service configurations"
  type = map(object({
    cpu              = number
    memory           = number
    command          = list(string)
    desired_count    = number
    target_group_key = string
    container_port   = number
  }))
  default = {
    backend = {
      cpu = 1024, memory = 2048
      command          = ["api"]
      desired_count    = 1
      target_group_key = "backend"
      container_port   = 8000
    }
    worker = {
      cpu = 512, memory = 1024
      command          = ["worker"]
      desired_count    = 1
      target_group_key = ""   # no ALB — background worker
      container_port   = 0
    }
    beat = {
      cpu = 256, memory = 512
      command          = ["beat"]
      desired_count    = 1
      target_group_key = ""   # no ALB — scheduler
      container_port   = 0
    }
    dashboard = {
      cpu = 256, memory = 512   # Fargate minimum for 256 CPU is 512 MB
      command          = []   # uses Dockerfile CMD (nginx)
      desired_count    = 1
      target_group_key = "dashboard"
      container_port   = 80
    }
    storefront = {
      cpu = 512, memory = 1024  # 768 CPU doesn't exist in Fargate; valid: 256/512/1024/2048/4096
      command          = []   # uses Dockerfile CMD (Next.js)
      desired_count    = 1
      target_group_key = "storefront"
      container_port   = 3000
    }
  }
}
