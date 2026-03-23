# =============================================================================
# CONCEPT: Data Sources
# Data sources READ existing information from AWS — they don't create anything.
# Think of them as "read-only" resources.
#
# We use data sources for things that already exist and we don't want
# to recreate: hosted zone, secrets, account info, AZs.
# =============================================================================

# Gets the current AWS account ID, user ARN, and region automatically.
# Useful so we don't hardcode account IDs anywhere.
data "aws_caller_identity" "current" {}

# Gets the list of available AZs in the current region.
# Used by the networking module to spread subnets across AZs.
data "aws_availability_zones" "available" {
  state = "available"
}

# CONCEPT: Data Source — reads an existing Route53 hosted zone
# We don't create this zone — it already exists (learnwithvinay.in)
# We just need its ID to add records to it.
data "aws_route53_zone" "main" {
  name         = "learnwithvinay.in"
  private_zone = false
}

# CONCEPT: Data Source — reads existing Secrets Manager secret
# saleor/prod already exists with all app secrets inside.
# We read it here and pass its ARN to ECS so containers can fetch secrets.
data "aws_secretsmanager_secret" "saleor" {
  name = "saleor/prod"
}

# Reads the actual secret values (the JSON blob inside the secret)
# We use specific keys from it to pass to the database module
data "aws_secretsmanager_secret_version" "saleor" {
  secret_id = data.aws_secretsmanager_secret.saleor.id
}
