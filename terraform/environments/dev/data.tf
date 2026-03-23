# =============================================================================
# CONCEPT: Data Sources — dev environment
# Dev reads from the same Route53 zone as prod (learnwithvinay.in)
# but creates a subdomain record: dev.learnwithvinay.in
#
# Dev has its OWN Secrets Manager secret: saleor/dev (separate from saleor/prod)
# =============================================================================

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Same hosted zone as prod — we add a CNAME record to it for dev subdomain
data "aws_route53_zone" "main" {
  name         = "learnwithvinay.in"
  private_zone = false
}

# Dev has its own separate secret in Secrets Manager
data "aws_secretsmanager_secret" "saleor_dev" {
  name = "saleor/dev"
}

data "aws_secretsmanager_secret_version" "saleor_dev" {
  secret_id = data.aws_secretsmanager_secret.saleor_dev.id
}
