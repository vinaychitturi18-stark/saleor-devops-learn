# =============================================================================
# CONCEPT: Outputs
# After terraform apply, these values are printed to your terminal.
# Useful to quickly get important info without going to AWS console.
# =============================================================================

output "alb_dns_name" {
  description = "ALB DNS name — before Route53 propagates, you can use this to test"
  value       = module.loadbalancer.alb_dns_name
}

output "domain" {
  description = "Production domain"
  value       = "https://${var.domain_name}"
}

output "ecs_cluster_name" {
  description = "ECS cluster name — use this to view services in AWS console"
  value       = module.compute.ecs_cluster_name
}

output "rds_endpoint" {
  description = "RDS endpoint — for reference (never expose publicly)"
  value       = module.database.rds_endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.database.redis_endpoint
  sensitive   = true
}

output "s3_media_bucket" {
  description = "S3 media bucket name"
  value       = module.storage.media_bucket_name
}

output "ecr_repository_urls" {
  description = "ECR repository URLs — use these in your CI/CD pipeline"
  value       = module.storage.ecr_repository_urls
}
