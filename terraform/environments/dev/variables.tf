# =============================================================================
# DEV ENVIRONMENT — VARIABLES
# Same structure as prod but different defaults — smaller, cheaper resources
# =============================================================================

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "app_name" {
  type    = string
  default = "saleor"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aws_account_id" {
  type    = string
  default = "249297038289"
}

# Different CIDR from prod — no overlap
variable "vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

# Dev has only 1 public subnet — just for cloudflared EC2
variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.1.0/24"]
}

# Dev has 2 private subnets — for ECS, RDS, Redis (needs 2 AZs for RDS)
variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.3.0/24", "10.1.4.0/24"]
}

# Smaller DB for dev
variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 10
}

variable "domain_name" {
  type    = string
  default = "dev.learnwithvinay.in"
}

variable "public_url" {
  type    = string
  default = "https://dev.learnwithvinay.in"
}

# Cloudflare tunnel token — get from Cloudflare Zero Trust dashboard
variable "cloudflare_tunnel_token" {
  type      = string
  sensitive = true
}

# Smaller ECS services for dev
variable "services" {
  type = map(object({
    cpu              = number
    memory           = number
    command          = list(string)
    desired_count    = number
    target_group_key = string
    container_port   = number
  }))
  default = {
    backend = {
      cpu = 512, memory = 1024
      command          = ["api"]
      desired_count    = 1
      target_group_key = "backend"
      container_port   = 8000
    }
    worker = {
      cpu = 256, memory = 512
      command          = ["worker"]
      desired_count    = 1
      target_group_key = ""
      container_port   = 0
    }
    beat = {
      cpu = 256, memory = 256
      command          = ["beat"]
      desired_count    = 1
      target_group_key = ""
      container_port   = 0
    }
    dashboard = {
      cpu = 256, memory = 512   # Fargate minimum for 256 CPU is 512 MB
      command          = []
      desired_count    = 1
      target_group_key = "dashboard"
      container_port   = 80
    }
    storefront = {
      cpu = 512, memory = 1024
      command          = []
      desired_count    = 1
      target_group_key = "storefront"
      container_port   = 3000
    }
  }
}
