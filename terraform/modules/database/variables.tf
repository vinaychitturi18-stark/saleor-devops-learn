# =============================================================================
# DATABASE MODULE — VARIABLES
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
  description = "VPC ID where the database will live"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the DB subnet group"
  type        = list(string)
}

variable "app_security_group_id" {
  description = "Security group ID of ECS tasks — only they can reach the DB"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance size. prod=db.t3.small, dev=db.t3.micro"
  type        = string
}

variable "db_allocated_storage" {
  description = "Storage size in GB. prod=20, dev=10"
  type        = number
}

variable "db_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "saleor"
}

variable "db_username" {
  description = "Master username for RDS"
  type        = string
  default     = "saleor"
}

variable "db_password" {
  description = "Master password for RDS — passed from Secrets Manager"
  type        = string
  sensitive   = true  # Terraform will never print this in logs or plan output
}

variable "redis_node_type" {
  description = "ElastiCache node type. prod=cache.t3.micro, dev=cache.t3.micro"
  type        = string
  default     = "cache.t3.micro"
}

variable "prevent_destroy" {
  description = "Whether to protect the DB from accidental deletion. true=prod, false=dev"
  type        = bool
  default     = true
}
