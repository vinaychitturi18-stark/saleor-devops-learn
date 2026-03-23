# =============================================================================
# DEV — Variable Values
# =============================================================================

aws_region     = "us-east-1"
app_name       = "saleor"
environment    = "dev"
aws_account_id = "249297038289"
domain_name    = "dev.learnwithvinay.in"
public_url     = "https://dev.learnwithvinay.in"

vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.1.0/24"]
private_subnet_cidrs = ["10.1.3.0/24", "10.1.4.0/24"]

db_instance_class    = "db.t3.micro"
db_allocated_storage = 10

# These sensitive values must be passed via environment variable or prompted:
# export TF_VAR_cloudflare_tunnel_token="your-token-here"
# export TF_VAR_db_password="your-password-here"
#
# OR create a terraform.tfvars.local (gitignored) file with:
# cloudflare_tunnel_token = "your-token-here"
# db_password             = "your-password-here"
