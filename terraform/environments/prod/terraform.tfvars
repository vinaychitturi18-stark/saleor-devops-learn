# =============================================================================
# PROD — Variable Values
# These override the defaults in variables.tf
# Never commit real secrets here — db_password comes from Secrets Manager
# =============================================================================

aws_region     = "us-east-1"
app_name       = "saleor"
environment    = "prod"
aws_account_id = "249297038289"
domain_name    = "learnwithvinay.in"
public_url     = "https://learnwithvinay.in"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]

db_instance_class    = "db.t3.small"
db_allocated_storage = 20

# db_password is NOT here — it comes from Secrets Manager in data.tf
# Terraform reads it with:
# jsondecode(data.aws_secretsmanager_secret_version.saleor.secret_string)["db_password"]
