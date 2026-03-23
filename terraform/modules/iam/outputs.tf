# =============================================================================
# IAM MODULE — OUTPUTS
# The compute module needs these role ARNs to attach to ECS task definitions
# =============================================================================

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role (used by ECS to start containers)"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role (used by app code at runtime)"
  value       = aws_iam_role.ecs_task.arn
}
