# =============================================================================
# CONCEPT: Import
# Import blocks bring existing AWS resources under Terraform management.
# Only "resource" blocks can be imported — NOT data sources.
# Data sources already read existing resources automatically.
#
# The Route53 hosted zone and Secrets Manager secret are read via data sources
# in data.tf — no import needed for those.
#
# Currently all prod resources (S3, ECR) were deleted and will be created fresh.
# This file is kept for reference — add import blocks here if you ever need
# to bring an existing resource under Terraform management.
#
# Example (if ECR repo already existed):
# import {
#   to = module.storage.aws_ecr_repository.this["saleor-backend"]
#   id = "saleor-backend"
# }
# =============================================================================
