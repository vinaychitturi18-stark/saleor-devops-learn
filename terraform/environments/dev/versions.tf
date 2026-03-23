# =============================================================================
# CONCEPT: Provider
# Same as prod — but this is a completely separate Terraform root.
# Running terraform apply here NEVER touches prod resources.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
