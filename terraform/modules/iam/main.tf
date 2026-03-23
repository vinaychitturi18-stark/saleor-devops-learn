# =============================================================================
# IAM MODULE — MAIN
# Creates the ECS Task Role — the identity that your running containers use.
#
# In AWS, every ECS task needs two IAM roles:
#
# 1. Task Execution Role — used by ECS ITSELF to:
#    - Pull the Docker image from ECR
#    - Write logs to CloudWatch
#    - Read secrets from Secrets Manager at startup
#    AWS provides a managed policy for this: AmazonECSTaskExecutionRolePolicy
#
# 2. Task Role — used by YOUR APPLICATION CODE while it runs to:
#    - Read/write files to S3
#    - Read secrets at runtime
#    This is what we create here.
# =============================================================================

# -----------------------------------------------------------------------------
# TASK EXECUTION ROLE
# ECS needs permission to start your container.
# The "assume_role_policy" says: "ECS is allowed to use this role"
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.app_name}-${var.environment}-ecs-execution-role"

  # This is a trust policy — it answers: "who is allowed to assume this role?"
  # We're saying: the ECS tasks service can use this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.app_name}-${var.environment}-ecs-execution-role"
    Environment = var.environment
  }
}

# Attach AWS managed policy — gives ECR pull + CloudWatch logs access
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Extra policy: allow reading secrets from Secrets Manager at container startup
resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "${var.app_name}-${var.environment}-execution-secrets"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "kms:Decrypt"
      ]
      Resource = "*"
    }]
  })
}

# -----------------------------------------------------------------------------
# TASK ROLE
# Your application code uses this role while it's running.
# Gives access to S3 (media uploads) and Secrets Manager (runtime secret reads)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task" {
  name = "${var.app_name}-${var.environment}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.app_name}-${var.environment}-ecs-task-role"
    Environment = var.environment
  }
}

# Policy: S3 access for media uploads/downloads
resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${var.app_name}-${var.environment}-task-s3"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        var.s3_media_bucket_arn,
        "${var.s3_media_bucket_arn}/*"
      ]
    }]
  })
}

# Policy: Secrets Manager access at runtime
resource "aws_iam_role_policy" "ecs_task_secrets" {
  name = "${var.app_name}-${var.environment}-task-secrets"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:us-east-1:${var.aws_account_id}:secret:${var.app_name}/${var.environment}*"
    }]
  })
}
