# =============================================================================
# CONCEPT: Import — dev environment
# Dev has fewer existing resources to import.
# The Route53 hosted zone is shared with prod (same zone, different record).
# Everything else in dev is brand new — no imports needed.
# =============================================================================

# No import blocks needed for dev — all resources are created fresh.
# The Route53 zone is read via data source (not imported) because
# Terraform doesn't need to manage the zone itself — just add records to it.
#
# If you had pre-existing dev resources (e.g. old ECR repos), you would add:
# import {
#   to = module.storage.aws_ecr_repository.this["saleor-backend-dev"]
#   id = "saleor-backend-dev"
# }
