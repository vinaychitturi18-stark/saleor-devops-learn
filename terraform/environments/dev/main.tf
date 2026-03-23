# =============================================================================
# DEV ENVIRONMENT — MAIN
# Same modules as prod — but different values:
#   - No NAT Gateway → VPC Endpoints instead
#   - Internal ALB → not internet-facing
#   - Cloudflare Tunnel → for developer access
#   - Separate ECR repos (-dev suffix)
#   - Smaller DB and ECS sizes
# =============================================================================

# -----------------------------------------------------------------------------
# STEP 1: Networking
# Key differences from prod:
#   enable_nat_gateway   = false  → no NAT GW (saves ~$32/month)
#   enable_vpc_endpoints = true   → VPC endpoints for AWS services instead
#   only 1 public subnet          → just for cloudflared EC2
# -----------------------------------------------------------------------------
module "networking" {
  source = "../../modules/networking"

  app_name             = var.app_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs   # only 1 public subnet
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = false  # dev uses VPC endpoints instead
  enable_vpc_endpoints = true   # ECS pulls images via VPC endpoints
}

# -----------------------------------------------------------------------------
# STEP 2: Storage — separate ECR repos for dev (saleor-backend-dev etc.)
# This means dev images never mix with prod images
# -----------------------------------------------------------------------------
module "storage" {
  source = "../../modules/storage"

  app_name       = var.app_name
  environment    = var.environment
  ecr_repo_names = [
    "saleor-backend-dev",
    "saleor-dashboard-dev",
    "saleor-storefront-dev"
  ]
}

# -----------------------------------------------------------------------------
# STEP 3: IAM — same structure as prod, different role names (dev suffix)
# -----------------------------------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  app_name            = var.app_name
  environment         = var.environment
  aws_account_id      = var.aws_account_id
  s3_media_bucket_arn = module.storage.media_bucket_arn
}

# -----------------------------------------------------------------------------
# STEP 4: Load Balancer
# Key difference: internal = true → ALB is NOT internet-facing
# Only reachable from inside the VPC (via Cloudflare tunnel)
# Uses private subnets (not public) since it's internal
# -----------------------------------------------------------------------------
module "loadbalancer" {
  source = "../../modules/loadbalancer"

  app_name          = var.app_name
  environment       = var.environment
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.private_subnet_ids  # internal ALB uses private subnets
  internal          = true          # dev = internal ALB
  domain_name       = var.domain_name
}

# ACM certificate DNS validation for dev.learnwithvinay.in
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

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = module.loadbalancer.certificate_arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# CONCEPT: Data Source — Route53 CNAME record
# dev.learnwithvinay.in → Cloudflare tunnel address
# (NOT pointing to ALB directly — goes through Cloudflare Zero Trust first)
# The actual tunnel hostname comes from Cloudflare dashboard after tunnel creation
resource "aws_route53_record" "dev" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.domain_name        # dev.learnwithvinay.in
  type    = "CNAME"
  ttl     = 300
  records = ["${var.cloudflare_tunnel_token}.cfargotunnel.com"]
  # ↑ Cloudflare tunnel address — traffic goes to Cloudflare first,
  #   auth happens there, then forwarded to cloudflared EC2 → internal ALB
}

# -----------------------------------------------------------------------------
# STEP 5: Cloudflare Tunnel EC2
# Only exists in dev — prod doesn't need it (public ALB)
# Runs cloudflared daemon that connects to Cloudflare's network
# -----------------------------------------------------------------------------
module "cloudflare_tunnel" {
  source = "../../modules/cloudflare_tunnel"

  app_name                = var.app_name
  environment             = var.environment
  vpc_id                  = module.networking.vpc_id
  public_subnet_id        = module.networking.public_subnet_ids[0]  # first (only) public subnet
  cloudflare_tunnel_token = var.cloudflare_tunnel_token
}

# -----------------------------------------------------------------------------
# STEP 6: Compute — same module, smaller sizes via variables
# -----------------------------------------------------------------------------
module "compute" {
  source = "../../modules/compute"

  app_name       = var.app_name
  environment    = var.environment
  aws_region     = var.aws_region
  aws_account_id = var.aws_account_id

  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids

  alb_security_group_id   = module.loadbalancer.alb_security_group_id
  target_group_arns        = module.loadbalancer.target_group_arns
  task_execution_role_arn  = module.iam.ecs_task_execution_role_arn
  task_role_arn            = module.iam.ecs_task_role_arn
  secrets_manager_arn      = data.aws_secretsmanager_secret.saleor_dev.arn
  s3_media_bucket          = module.storage.media_bucket_name
  ecr_repository_urls      = module.storage.ecr_repository_urls
  public_url               = var.public_url
  services                 = var.services
}

# -----------------------------------------------------------------------------
# STEP 7: Database — smaller sizes, prevent_destroy = false
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
  prevent_destroy       = false  # dev DB can be destroyed safely

  db_password = jsondecode(
    data.aws_secretsmanager_secret_version.saleor_dev.secret_string
  )["db_password"]
}
