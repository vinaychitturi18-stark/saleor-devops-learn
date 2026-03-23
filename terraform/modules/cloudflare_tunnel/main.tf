# =============================================================================
# CLOUDFLARE TUNNEL MODULE — MAIN
# Creates: EC2 instance running cloudflared daemon
#
# How it works:
# 1. EC2 starts and runs the user_data script below
# 2. Script installs cloudflared and connects to Cloudflare using the token
# 3. cloudflared opens an OUTBOUND tunnel to Cloudflare's network
# 4. When a developer visits dev.learnwithvinay.in:
#    - Cloudflare authenticates them (Google login)
#    - Pushes the request through the tunnel to this EC2
#    - EC2 forwards it to the internal ALB
#
# Security: ZERO inbound ports open — the tunnel is purely outbound
# =============================================================================

# CONCEPT: Data Source
# Fetch the latest Amazon Linux 2023 AMI ID automatically.
# This means the code always uses the latest patched version —
# no hardcoding AMI IDs that go stale.
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------------------------------------
# SECURITY GROUP — cloudflared EC2
# Inbound:  NOTHING — no ports open at all
# Outbound: HTTPS (443) to reach Cloudflare servers
#           Also port 7844 (Cloudflare's QUIC protocol — faster tunneling)
# -----------------------------------------------------------------------------
resource "aws_security_group" "cloudflared" {
  name        = "${var.app_name}-${var.environment}-cloudflared-sg"
  description = "Cloudflare tunnel EC2 — outbound only, zero inbound"
  vpc_id      = var.vpc_id

  # No ingress rules = nothing can reach this instance from outside

  egress {
    description = "HTTPS to Cloudflare"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "QUIC to Cloudflare (faster tunnel protocol)"
    from_port   = 7844
    to_port     = 7844
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP to internal ALB (forwarding requests)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS to internal ALB (forwarding requests)"
    from_port   = 8000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.app_name}-${var.environment}-cloudflared-sg"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# EC2 INSTANCE — cloudflared daemon
# t2.micro = free tier eligible
# user_data = shell script that runs automatically on first boot
# -----------------------------------------------------------------------------
resource "aws_instance" "cloudflared" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.cloudflared.id]

  # No SSH key — we never need to SSH in
  # If needed, use AWS Systems Manager Session Manager instead

  associate_public_ip_address = true  # needs public IP to reach Cloudflare

  # user_data runs once when EC2 first boots
  # It installs cloudflared and connects to Cloudflare using the token
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Install cloudflared
    curl -L --output /tmp/cloudflared.rpm \
      https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-x86_64.rpm
    rpm -ivh /tmp/cloudflared.rpm

    # Connect to Cloudflare tunnel using the token
    # The token tells cloudflared which tunnel to connect to
    cloudflared service install ${var.cloudflare_tunnel_token}
    systemctl start cloudflared
    systemctl enable cloudflared
  EOF

  tags = {
    Name        = "${var.app_name}-${var.environment}-cloudflared"
    Environment = var.environment
  }
}
