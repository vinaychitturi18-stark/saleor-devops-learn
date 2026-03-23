# =============================================================================
# COMPUTE MODULE — MAIN
# Creates: ECS Cluster + Security Group + 5 ECS Services via for_each
#
# CONCEPT: for_each on a map of objects
# This is the most powerful use of for_each. We define all 5 services
# (backend, worker, beat, dashboard, storefront) in a single variable map.
# One resource block creates all 5 task definitions and services.
#
# Without for_each: 5 × 3 = 15 resource blocks (task def + service + log group)
# With for_each:    3 resource blocks total — one of each, loops 5 times
# =============================================================================

# -----------------------------------------------------------------------------
# ECS CLUSTER
# A logical grouping for all our services.
# With Fargate, the cluster is just a name — no EC2 instances to manage.
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = "${var.app_name}-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"  # enables CloudWatch metrics per service
  }

  tags = {
    Name        = "${var.app_name}-${var.environment}"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# SECURITY GROUP — ECS Tasks
# Controls what traffic can reach the containers.
# Inbound: only from ALB (on any port — each service uses a different port)
# Outbound: everything (to reach RDS, Redis, ECR, S3, internet)
# -----------------------------------------------------------------------------
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.app_name}-${var.environment}-ecs-tasks-sg"
  description = "Allow traffic from ALB to ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    description     = "All traffic from ALB"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.app_name}-${var.environment}-ecs-tasks-sg"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# CLOUDWATCH LOG GROUPS
# CONCEPT: for_each — one log group per service
# Each service gets its own log group so you can view logs per service
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  for_each = var.services

  name              = "/ecs/${var.app_name}-${var.environment}/${each.key}"
  retention_in_days = 7  # keep logs for 7 days — adjust as needed

  tags = {
    Name        = "${var.app_name}-${var.environment}-${each.key}"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# ECS TASK DEFINITIONS
# CONCEPT: for_each — one task definition per service
#
# A task definition is like a blueprint for a container:
# - Which Docker image to use
# - How much CPU/memory to give it
# - What environment variables and secrets to inject
# - Where to send logs
#
# each.key  = service name ("backend", "worker", "beat", "dashboard", "storefront")
# each.value = the object with cpu, memory, command, etc.
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "this" {
  for_each = var.services

  family                   = "${var.app_name}-${var.environment}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"  # required for Fargate
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = var.task_execution_role_arn  # ECS uses this to start container
  task_role_arn            = var.task_role_arn             # App uses this at runtime

  container_definitions = jsonencode([{
    name  = each.key
    # Pick the right ECR image for each service
    # backend/worker/beat all use the same backend image
    # dashboard uses dashboard image, storefront uses storefront image
    image = lookup(
      var.ecr_repository_urls,
      contains(["worker", "beat"], each.key) ? "${var.app_name}-backend" : "${var.app_name}-${each.key}",
      lookup(var.ecr_repository_urls, "${var.app_name}-backend", "")
    )

    command = length(each.value.command) > 0 ? each.value.command : null

    # Environment variables — non-sensitive config
    environment = [
      { name = "AWS_STORAGE_BUCKET_NAME",  value = var.s3_media_bucket },
      { name = "AWS_MEDIA_BUCKET_NAME",    value = var.s3_media_bucket },
      { name = "AWS_S3_REGION_NAME",       value = var.aws_region },
      { name = "AWS_MEDIA_CUSTOM_DOMAIN",  value = "${var.s3_media_bucket}.s3.amazonaws.com" },
      { name = "AWS_DEFAULT_ACL",          value = "public-read" },
      { name = "AWS_QUERYSTRING_AUTH",     value = "False" },
      { name = "PUBLIC_URL",               value = var.public_url },
      { name = "STOREFRONT_URL",           value = var.public_url },
      { name = "DASHBOARD_URL",            value = "${var.public_url}/dashboard/" },
    ]

    # Secrets — pulled from Secrets Manager at container startup
    # ECS reads these from Secrets Manager and injects as env vars
    # Your app code just reads them as normal env vars — never sees Secrets Manager
    secrets = [
      { name = "DATABASE_URL",      valueFrom = "${var.secrets_manager_arn}:DATABASE_URL::" },
      { name = "SECRET_KEY",        valueFrom = "${var.secrets_manager_arn}:SECRET_KEY::" },
      { name = "ALLOWED_HOSTS",     valueFrom = "${var.secrets_manager_arn}:ALLOWED_HOSTS::" },
      { name = "CELERY_BROKER_URL", valueFrom = "${var.secrets_manager_arn}:CELERY_BROKER_URL::" },
      { name = "CACHE_URL",         valueFrom = "${var.secrets_manager_arn}:CACHE_URL::" },
      { name = "EMAIL_URL",         valueFrom = "${var.secrets_manager_arn}:EMAIL_URL::" },
    ]

    portMappings = each.value.container_port > 0 ? [{
      containerPort = each.value.container_port
      protocol      = "tcp"
    }] : []

    # Send all container logs to CloudWatch
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this[each.key].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    essential = true
  }])

  tags = {
    Name        = "${var.app_name}-${var.environment}-${each.key}"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# ECS SERVICES
# CONCEPT: for_each — one service per entry in var.services
#
# A service keeps your task running. If a container crashes, ECS
# automatically starts a new one to maintain desired_count.
#
# Services with a target_group_key get registered behind the ALB.
# Worker and Beat have no ALB (they process background jobs, not HTTP).
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "this" {
  for_each = var.services

  name            = "${var.app_name}-${var.environment}-${each.key}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this[each.key].arn
  desired_count   = each.value.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false  # private subnet — no public IP needed
  }

  # Only attach to ALB if this service has a target group
  dynamic "load_balancer" {
    for_each = each.value.target_group_key != "" ? [1] : []
    content {
      target_group_arn = var.target_group_arns[each.value.target_group_key]
      container_name   = each.key
      container_port   = each.value.container_port
    }
  }

  # Wait for ALB target group to exist before creating service
  depends_on = [var.target_group_arns]

  # CONCEPT: lifecycle
  # Ignore changes to desired_count — allows manual scaling without
  # Terraform reverting it on next apply
  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = {
    Name        = "${var.app_name}-${var.environment}-${each.key}"
    Environment = var.environment
  }
}
