# =============================================================================
# PROD ENVIRONMENT — MAIN
# This file calls all modules and wires them together.
# Think of this as the "director" — it tells each module what values to use.
#
# CONCEPT: Modules
# Each module call is like calling a function:
#   module "networking" { ... }  →  runs all code in modules/networking/
# The outputs from one module become inputs to the next.
# =============================================================================

# -----------------------------------------------------------------------------
# STEP 1: Networking — must be first, everything else needs VPC + subnet IDs
# -----------------------------------------------------------------------------
module "networking" {
  source = "../../modules/networking"

  app_name             = var.app_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = true   # prod uses NAT Gateway for outbound internet
  enable_vpc_endpoints = false  # prod doesn't need VPC endpoints (has NAT GW)
}

# -----------------------------------------------------------------------------
# STEP 2: Storage — create S3 + ECR before IAM (IAM needs S3 bucket ARN)
# -----------------------------------------------------------------------------
module "storage" {
  source = "../../modules/storage"

  app_name       = var.app_name
  environment    = var.environment
  ecr_repo_names = ["saleor-backend", "saleor-dashboard", "saleor-storefront"]
}

# -----------------------------------------------------------------------------
# STEP 3: IAM — needs S3 bucket ARN from storage module
# -----------------------------------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  app_name            = var.app_name
  environment         = var.environment
  aws_account_id      = var.aws_account_id
  s3_media_bucket_arn = module.storage.media_bucket_arn
  # ↑ output from storage module used as input here
}

# -----------------------------------------------------------------------------
# STEP 4: Load Balancer — needs VPC + subnet IDs from networking module
# -----------------------------------------------------------------------------
module "loadbalancer" {
  source = "../../modules/loadbalancer"

  app_name          = var.app_name
  environment       = var.environment
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  internal          = false             # prod = internet-facing
  domain_name       = var.domain_name
}

# ACM certificate DNS validation — Route53 record that proves we own the domain
# Terraform creates this automatically using the output from the loadbalancer module
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in module.loadbalancer.certificate_domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

# Wait for certificate to be fully validated before using it
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = module.loadbalancer.certificate_arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Route53 A record — points learnwithvinay.in to the ALB
resource "aws_route53_record" "main" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.loadbalancer.alb_dns_name
    zone_id                = module.loadbalancer.alb_zone_id
    evaluate_target_health = true
  }
}

# Route53 A record — www.learnwithvinay.in also points to ALB
resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.loadbalancer.alb_dns_name
    zone_id                = module.loadbalancer.alb_zone_id
    evaluate_target_health = true
  }
}

# -----------------------------------------------------------------------------
# STEP 5: Compute — needs outputs from networking, iam, storage, loadbalancer
# This is where all modules come together
# -----------------------------------------------------------------------------
module "compute" {
  source = "../../modules/compute"

  app_name    = var.app_name
  environment = var.environment
  aws_region  = var.aws_region
  aws_account_id = var.aws_account_id

  # From networking module
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids

  # From loadbalancer module
  alb_security_group_id = module.loadbalancer.alb_security_group_id
  target_group_arns     = module.loadbalancer.target_group_arns

  # From IAM module
  task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  task_role_arn           = module.iam.ecs_task_role_arn

  # From data sources (existing Secrets Manager secret)
  secrets_manager_arn = data.aws_secretsmanager_secret.saleor.arn

  # From storage module
  s3_media_bucket    = module.storage.media_bucket_name
  ecr_repository_urls = module.storage.ecr_repository_urls

  public_url = var.public_url
  services   = var.services
}

# -----------------------------------------------------------------------------
# STEP 6: Database — needs VPC, subnets, and ECS security group
# ECS security group from compute module is used to restrict DB access
# -----------------------------------------------------------------------------
module "database" {
  source = "../../modules/database"

  app_name              = var.app_name
  environment           = var.environment
  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnet_ids
  app_security_group_id = module.compute.ecs_tasks_security_group_id
  db_instance_class     = var.db_instance_class
  db_allocated_storage  = var.db_allocated_storage
  prevent_destroy       = true  # NEVER delete prod database

  # Password read from existing Secrets Manager secret via data source
  db_password = jsondecode(data.aws_secretsmanager_secret_version.saleor.secret_string)["db_password"]
}
