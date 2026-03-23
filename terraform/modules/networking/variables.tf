# =============================================================================
# NETWORKING MODULE — VARIABLES
# These are the inputs this module accepts.
# The environment (dev/prod) passes values for these when calling this module.
# =============================================================================

# CONCEPT: Variable
# Every module defines what inputs it needs. The caller must provide them.

variable "app_name" {
  description = "Application name — used as a prefix for all resource names"
  type        = string
}

variable "environment" {
  description = "Environment name — dev or prod"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. prod=10.0.0.0/16, dev=10.1.0.0/16"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDRs for public subnets. One per AZ."
  type        = list(string)
  # prod example: ["10.0.1.0/24", "10.0.2.0/24"]
  # dev example:  ["10.1.1.0/24"]  ← only 1 public subnet in dev (just for cloudflared)
}

variable "private_subnet_cidrs" {
  description = "List of CIDRs for private subnets. One per AZ."
  type        = list(string)
  # prod example: ["10.0.3.0/24", "10.0.4.0/24"]
  # dev example:  ["10.1.3.0/24", "10.1.4.0/24"]
}

variable "enable_nat_gateway" {
  description = "Whether to create NAT Gateway. true=prod, false=dev (dev uses VPC endpoints)"
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Whether to create VPC endpoints for AWS services. true=dev, false=prod"
  type        = bool
  default     = false
}
