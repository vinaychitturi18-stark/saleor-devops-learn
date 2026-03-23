# =============================================================================
# CONCEPT: Backend
# Same S3 bucket as prod — but DIFFERENT key.
# prod → saleor/prod/terraform.tfstate
# dev  → saleor/dev/terraform.tfstate   ← completely separate state file
#
# These two state files never interact with each other.
# You can destroy dev without affecting prod state at all.
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "saleor-terraform-state-learnwithvinay"
    key            = "saleor/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "saleor-terraform-locks"
    encrypt        = true
  }
}
