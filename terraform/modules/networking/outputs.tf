# =============================================================================
# NETWORKING MODULE — OUTPUTS
# These values are returned to whoever calls this module.
# Other modules (loadbalancer, compute, database) need these IDs.
# =============================================================================

# CONCEPT: Output
# Modules communicate with each other through outputs.
# Example: the compute module needs to know which subnets to put ECS tasks in.
# It gets that by referencing module.networking.private_subnet_ids

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
  # [*] = collect all instances created by count into a list
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  value       = aws_subnet.private[*].cidr_block
}
