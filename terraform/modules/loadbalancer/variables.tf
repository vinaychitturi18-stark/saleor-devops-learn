# =============================================================================
# LOAD BALANCER MODULE — VARIABLES
# =============================================================================

variable "app_name" {
  description = "Application name prefix"
  type        = string
}

variable "environment" {
  description = "Environment name — dev or prod"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the ALB will live"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB (prod). Private for internal ALB (dev)."
  type        = list(string)
}

variable "internal" {
  description = "Whether the ALB is internal (true=dev) or internet-facing (false=prod)"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener. Empty string if no HTTPS."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for the ALB. prod=learnwithvinay.in, dev=dev.learnwithvinay.in"
  type        = string
}
