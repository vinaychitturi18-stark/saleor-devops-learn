# =============================================================================
# COMPUTE MODULE — OUTPUTS
# =============================================================================

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.this.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.this.arn
}

output "ecs_tasks_security_group_id" {
  description = "Security group ID of ECS tasks — needed by database module"
  value       = aws_security_group.ecs_tasks.id
}

output "service_names" {
  description = "Map of service name → ECS service name"
  value       = { for name, svc in aws_ecs_service.this : name => svc.name }
}
