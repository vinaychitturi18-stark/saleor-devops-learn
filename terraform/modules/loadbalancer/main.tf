# =============================================================================
# LOAD BALANCER MODULE — MAIN
# Creates: ALB, Security Group, Target Groups, Listeners, ACM Certificate
#
# Path-based routing:
#   /graphql/* /media/* /thumbnail/*  → backend  (port 8000)
#   /dashboard/*                   → dashboard (port 80)
#   /*                             → storefront (port 3000)
# =============================================================================

# -----------------------------------------------------------------------------
# SECURITY GROUP — ALB
# prod: allow 80 + 443 from anywhere (0.0.0.0/0) — public traffic
# dev:  allow 443 from anywhere — but ALB is internal so only VPN can reach it
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.app_name}-${var.environment}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.app_name}-${var.environment}-alb-sg"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# APPLICATION LOAD BALANCER
# internal = true  → dev  (only reachable inside VPC via Cloudflare tunnel)
# internal = false → prod (internet-facing, reachable by everyone)
# -----------------------------------------------------------------------------
resource "aws_lb" "this" {
  name               = "${var.app_name}-${var.environment}-alb"
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  # Access logs disabled to keep costs down for learning
  # In prod at a real company you'd enable this for debugging
  enable_deletion_protection = false

  tags = {
    Name        = "${var.app_name}-${var.environment}-alb"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# ACM CERTIFICATE
# Automatically provisions a TLS certificate for our domain.
# Uses DNS validation — Terraform creates a Route53 record to prove
# we own the domain, then ACM issues the certificate.
# -----------------------------------------------------------------------------
resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  # lifecycle create_before_destroy — if certificate needs replacing,
  # create the new one first so there's no downtime
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.app_name}-${var.environment}-cert"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# TARGET GROUPS
# A target group is a group of destinations that ALB can route traffic to.
# We have 3: backend, dashboard, storefront
#
# for_each on a map — the map key is the name, value has port + health check path
# -----------------------------------------------------------------------------
locals {
  target_groups = {
    backend = {
      port              = 8000
      health_check_path = "/health/"
    }
    dashboard = {
      port              = 80
      health_check_path = "/dashboard/"
    }
    storefront = {
      port              = 3000
      health_check_path = "/"
    }
  }
}

resource "aws_lb_target_group" "this" {
  for_each = local.target_groups

  name        = "${var.app_name}-${var.environment}-${each.key}-tg"
  port        = each.value.port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"  # Fargate uses IP targets, not instance targets

  health_check {
    path                = each.value.health_check_path
    healthy_threshold   = 2    # 2 consecutive successes = healthy
    unhealthy_threshold = 3    # 3 consecutive failures = unhealthy
    timeout             = 10
    interval            = 30
    matcher             = "200-399"
  }

  tags = {
    Name        = "${var.app_name}-${var.environment}-${each.key}-tg"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# HTTP LISTENER (port 80)
# Redirects all HTTP traffic to HTTPS — best practice
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"  # permanent redirect
    }
  }
}

# -----------------------------------------------------------------------------
# HTTPS LISTENER (port 443)
# Default action sends to storefront.
# Rules below override this for specific paths.
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.this.arn

  # Default: send everything to storefront
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["storefront"].arn
  }
}

# -----------------------------------------------------------------------------
# LISTENER RULES — Path-based routing
# Rules are evaluated top to bottom by priority (lower number = checked first)
# -----------------------------------------------------------------------------

# /graphql/* → backend
resource "aws_lb_listener_rule" "graphql" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["backend"].arn
  }

  condition {
    path_pattern { values = ["/graphql/*"] }
  }
}

# /media/* → backend
resource "aws_lb_listener_rule" "media" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["backend"].arn
  }

  condition {
    path_pattern { values = ["/media/*"] }
  }
}

# /thumbnail/* → backend (product image thumbnails)
resource "aws_lb_listener_rule" "static" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["backend"].arn
  }

  condition {
    path_pattern { values = ["/thumbnail/*"] }
  }
}

# /dashboard/* → dashboard
resource "aws_lb_listener_rule" "dashboard" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 40

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["dashboard"].arn
  }

  condition {
    path_pattern { values = ["/dashboard/*"] }
  }
}
