# =============================================================================
# NETWORKING MODULE — MAIN
# Creates: VPC, subnets, IGW, route tables, NAT GW (prod) or VPC endpoints (dev)
# =============================================================================

# CONCEPT: Data Source
# We don't hardcode AZ names like "us-east-1a".
# Instead we ask AWS: "give me the available AZs in this region."
# This makes the code portable — works in any region automatically.
data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------------------
# VPC
# The private network that contains all our resources.
# Nothing inside can be reached from the internet unless we explicitly allow it.
# -----------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true  # allows EC2s to get DNS names like ip-10-0-1-5.ec2.internal
  enable_dns_support   = true  # required for VPC endpoints to work

  tags = {
    Name        = "${var.app_name}-${var.environment}-vpc"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# PUBLIC SUBNETS
# CONCEPT: count
# Instead of writing one resource block per subnet, we use count.
# Terraform creates one subnet for each item in var.public_subnet_cidrs.
# count.index = 0, 1, 2... lets us pick the right CIDR and AZ for each.
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)  # prod=2, dev=1

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true  # instances in public subnet get a public IP

  tags = {
    Name        = "${var.app_name}-${var.environment}-public-${count.index + 1}"
    Environment = var.environment
    Type        = "public"
  }
}

# -----------------------------------------------------------------------------
# PRIVATE SUBNETS
# Same count pattern — one subnet per CIDR in the list.
# ECS tasks, RDS, Redis all live here. No direct internet access.
# -----------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)  # prod=2, dev=2

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${var.app_name}-${var.environment}-private-${count.index + 1}"
    Environment = var.environment
    Type        = "private"
  }
}

# -----------------------------------------------------------------------------
# INTERNET GATEWAY
# The door between the VPC and the public internet.
# Only public subnets use this. Private subnets use NAT GW or VPC endpoints.
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${var.app_name}-${var.environment}-igw"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# PUBLIC ROUTE TABLE
# Tells public subnets: "send all internet traffic (0.0.0.0/0) to the IGW"
# -----------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name        = "${var.app_name}-${var.environment}-public-rt"
    Environment = var.environment
  }
}

# Associate each public subnet with the public route table
# count again — one association per public subnet
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# NAT GATEWAY (prod only)
# CONCEPT: Lifecycle via conditional — only created when enable_nat_gateway=true
# NAT GW sits in a public subnet and lets private subnet resources reach the
# internet (for pulling Docker images, etc.) without being reachable from internet.
#
# count = 1 if enabled, 0 if disabled → Terraform creates or skips it
# -----------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = {
    Name        = "${var.app_name}-${var.environment}-nat-eip"
    Environment = var.environment
  }
}

resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id  # NAT GW lives in the first public subnet

  tags = {
    Name        = "${var.app_name}-${var.environment}-nat-gw"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.this]
}

# -----------------------------------------------------------------------------
# PRIVATE ROUTE TABLE
# Tells private subnets where to send outbound traffic.
# prod: goes to NAT Gateway
# dev:  no NAT — traffic to AWS services goes through VPC endpoints instead
# -----------------------------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  # Only add NAT route if NAT gateway is enabled (prod)
  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.this[0].id
    }
  }

  tags = {
    Name        = "${var.app_name}-${var.environment}-private-rt"
    Environment = var.environment
  }
}

# Associate each private subnet with the private route table
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------------
# VPC ENDPOINTS (dev only)
# When enable_nat_gateway=false (dev), ECS Fargate tasks have no internet access.
# VPC endpoints let them reach AWS services (ECR, S3, Secrets Manager, etc.)
# through AWS's private network — no internet needed, no NAT cost.
#
# Interface endpoints = ENIs in your subnet (cost ~$7/month each)
# Gateway endpoints   = free, only for S3 and DynamoDB
# -----------------------------------------------------------------------------

# Security group for VPC interface endpoints
resource "aws_security_group" "vpc_endpoints" {
  count = var.enable_vpc_endpoints ? 1 : 0

  name        = "${var.app_name}-${var.environment}-vpc-endpoints-sg"
  description = "Allow HTTPS from within VPC to reach VPC endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]  # only allow traffic from within VPC
  }

  tags = {
    Name        = "${var.app_name}-${var.environment}-vpc-endpoints-sg"
    Environment = var.environment
  }
}

# Interface endpoints for services ECS Fargate needs
locals {
  # These are the AWS services Fargate needs to function without internet
  interface_endpoint_services = var.enable_vpc_endpoints ? [
    "ecr.api",          # ECR API (auth)
    "ecr.dkr",          # ECR Docker registry (pull images)
    "ecs",              # ECS control plane
    "ecs-agent",        # ECS agent on Fargate
    "ecs-telemetry",    # ECS telemetry
    "secretsmanager",   # Secrets Manager
    "logs",             # CloudWatch Logs
    "sts",              # STS (for IAM role assumption)
  ] : []
}

resource "aws_vpc_endpoint" "interface" {
  # CONCEPT: for_each on a list converted to a set
  for_each = toset(local.interface_endpoint_services)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.us-east-1.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true  # so services resolve to private IPs automatically

  tags = {
    Name        = "${var.app_name}-${var.environment}-endpoint-${each.value}"
    Environment = var.environment
  }
}

# S3 Gateway endpoint — free, routes S3 traffic through AWS backbone
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name        = "${var.app_name}-${var.environment}-endpoint-s3"
    Environment = var.environment
  }
}
