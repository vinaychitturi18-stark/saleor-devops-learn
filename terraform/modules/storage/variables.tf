# =============================================================================
# STORAGE MODULE — VARIABLES
# =============================================================================

variable "app_name" {
  description = "Application name prefix"
  type        = string
}

variable "environment" {
  description = "Environment name — dev or prod"
  type        = string
}

variable "ecr_repo_names" {
  description = "List of ECR repository names to create"
  type        = list(string)
  # prod: ["saleor-backend", "saleor-dashboard", "saleor-storefront"]
  # dev:  ["saleor-backend-dev", "saleor-dashboard-dev", "saleor-storefront-dev"]
}
