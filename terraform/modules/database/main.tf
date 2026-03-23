# =============================================================================
# DATABASE MODULE — MAIN
# Creates: RDS PostgreSQL 15 + ElastiCache Redis 7
#
# CONCEPT: lifecycle — prevent_destroy
# The most critical lifecycle rule. On prod, if you accidentally run
# `terraform destroy`, Terraform will REFUSE to delete the RDS instance.
# It throws an error instead. Your data is safe.
#
# CONCEPT: Security Groups
# Databases are never exposed to the internet. We use security groups to
# create a firewall rule: only ECS tasks can connect to RDS/Redis.
# =============================================================================

# -----------------------------------------------------------------------------
# SECURITY GROUP — RDS
# Only allows traffic from the ECS tasks security group on port 5432
# -----------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${var.app_name}-${var.environment}-rds-sg"
  description = "Allow PostgreSQL access from ECS tasks only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]  # only ECS tasks, nothing else
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.app_name}-${var.environment}-rds-sg"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# SECURITY GROUP — Redis
# Only allows traffic from ECS tasks on port 6379
# -----------------------------------------------------------------------------
resource "aws_security_group" "redis" {
  name        = "${var.app_name}-${var.environment}-redis-sg"
  description = "Allow Redis access from ECS tasks only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from ECS tasks"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.app_name}-${var.environment}-redis-sg"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# RDS SUBNET GROUP
# Tells RDS which subnets it can use. Must span at least 2 AZs (AWS requirement)
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name       = "${var.app_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name        = "${var.app_name}-${var.environment}-db-subnet-group"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# RDS POSTGRESQL 15
# CONCEPT: lifecycle — prevent_destroy
#
# prevent_destroy = true means Terraform will ERROR if you try to destroy this.
# This is the most important safety net for production databases.
#
# Try running `terraform destroy` on prod — you'll see:
# "Error: Instance cannot be destroyed"
#
# The only way to delete it is to:
# 1. Set prevent_destroy = false in the code
# 2. Run terraform apply (to update the state)
# 3. Then run terraform destroy
# This forces you to be intentional about deleting production data.
# -----------------------------------------------------------------------------
resource "aws_db_instance" "postgres" {
  identifier = "${var.app_name}-${var.environment}-postgres"

  # Engine
  engine         = "postgres"
  engine_version = "15"
  instance_class = var.db_instance_class

  # Storage
  allocated_storage     = var.db_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true

  # Credentials
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false  # never expose DB to internet

  # Backup
  backup_retention_period = 7     # keep 7 days of automated backups
  skip_final_snapshot     = false # take a snapshot before deletion
  final_snapshot_identifier = "${var.app_name}-${var.environment}-final-snapshot"

  # Maintenance
  auto_minor_version_upgrade = true
  deletion_protection        = var.prevent_destroy  # AWS-level protection too

  # CONCEPT: lifecycle
  lifecycle {
    prevent_destroy = true  # Terraform-level protection
    # Even if prevent_destroy var is false (dev), Terraform still protects it
    # To truly allow deletion in dev, change this to false

    ignore_changes = [
      password,  # password managed separately — don't show drift if rotated
    ]
  }

  tags = {
    Name        = "${var.app_name}-${var.environment}-postgres"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# ELASTICACHE SUBNET GROUP
# Same concept as RDS subnet group — tells Redis which subnets to use
# -----------------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.app_name}-${var.environment}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name        = "${var.app_name}-${var.environment}-redis-subnet-group"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# ELASTICACHE REDIS 7
# Important: cluster_mode DISABLED — Saleor's Celery uses Redis SELECT command
# which only works when cluster mode is off
# -----------------------------------------------------------------------------
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.app_name}-${var.environment}-redis"
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1         # single node (no replication in this setup)
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  tags = {
    Name        = "${var.app_name}-${var.environment}-redis"
    Environment = var.environment
  }
}
