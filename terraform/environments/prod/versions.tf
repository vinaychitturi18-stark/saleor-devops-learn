# =============================================================================
# CONCEPT: Provider
# Tells Terraform which cloud provider to use and which version.
# "~> 5.0" means: any 5.x version but not 6.x
# This prevents surprise breaking changes from major version upgrades.
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
