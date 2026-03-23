# =============================================================================
# DEV ENVIRONMENT — OUTPUTS
# =============================================================================

output "cloudflared_ec2_id" {
  description = "EC2 instance ID of the Cloudflare tunnel"
  value       = module.cloudflare_tunnel.instance_id
}

output "internal_alb_dns" {
  description = "Internal ALB DNS — only reachable via Cloudflare tunnel"
  value       = module.loadbalancer.alb_dns_name
}

output "dev_domain" {
  description = "Dev domain — access via browser after Cloudflare login"
  value       = "https://${var.domain_name}"
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.compute.ecs_cluster_name
}

output "ecr_repository_urls" {
  description = "ECR repository URLs for dev CI/CD"
  value       = module.storage.ecr_repository_urls
}
