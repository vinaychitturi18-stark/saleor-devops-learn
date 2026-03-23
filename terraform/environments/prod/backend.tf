# =============================================================================
# CONCEPT: Backend
# Tells Terraform WHERE to store the state file.
#
# Without this block → state stored locally on your laptop (dangerous)
# With this block    → state stored in S3 (safe, shared, versioned)
#
# key = path inside the S3 bucket where the state file lives
# prod uses "saleor/prod/terraform.tfstate"
# dev  uses "saleor/dev/terraform.tfstate"  ← completely separate file
#
# dynamodb_table → used for locking (prevents two applies at the same time)
# Both prod and dev share the same lock table — they just use different lock keys
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "saleor-terraform-state-learnwithvinay"
    key            = "saleor/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "saleor-terraform-locks"
    encrypt        = true
  }
}
