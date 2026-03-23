# =============================================================================
# CLOUDFLARE TUNNEL MODULE — VARIABLES
# =============================================================================

variable "app_name" {
  description = "Application name prefix"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the EC2 instance will live"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID for the cloudflared EC2 instance"
  type        = string
}

variable "cloudflare_tunnel_token" {
  description = "Cloudflare tunnel token — get this from Cloudflare Zero Trust dashboard after creating the tunnel"
  type        = string
  sensitive   = true
}
