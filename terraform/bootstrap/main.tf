# =============================================================================
# BOOTSTRAP — Run once before anything else
#
# Creates:
#   1. S3 bucket  → stores all Terraform state files
#   2. DynamoDB   → locks state so two people can't apply at the same time
#
# After running this, all other Terraform environments (dev/prod) will
# point their backend.tf to this bucket.
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5.0"
}

# CONCEPT: Provider
# Tells Terraform which cloud to talk to and which region to use.
provider "aws" {
  region = "us-east-1"
}

# CONCEPT: Resource
# S3 bucket to store all state files.
# Note: bootstrap intentionally has NO backend block — it stores state
# locally. This is the one exception because the bucket doesn't exist yet.
resource "aws_s3_bucket" "terraform_state" {
  bucket = "saleor-terraform-state-learnwithvinay"

  # prevent_destroy = true so you never accidentally delete all your state
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name    = "saleor-terraform-state"
    Purpose = "Terraform remote state storage"
  }
}

# Versioning on — every state file change is kept.
# If you ever corrupt state, you can roll back to a previous version.
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state at rest — state files contain sensitive data (DB passwords etc)
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access — state files must NEVER be public
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CONCEPT: Resource
# DynamoDB table for state locking.
# When you run terraform apply, Terraform writes a lock entry here.
# If someone else tries to apply at the same time, they get an error.
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "saleor-terraform-locks"
  billing_mode = "PAY_PER_REQUEST" # no upfront cost, pay per use
  hash_key     = "LockID"          # Terraform expects exactly this key name

  attribute {
    name = "LockID"
    type = "S" # S = String
  }

  tags = {
    Name    = "saleor-terraform-locks"
    Purpose = "Terraform state locking"
  }
}

# CONCEPT: Output
# After apply, Terraform prints these values.
# Useful to copy the bucket name into your backend.tf files.
output "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}
