# =============================================================================
# CLOUDFLARE TUNNEL MODULE — OUTPUTS
# =============================================================================

output "instance_id" {
  description = "EC2 instance ID of the cloudflared daemon"
  value       = aws_instance.cloudflared.id
}

output "instance_public_ip" {
  description = "Public IP of the cloudflared EC2 — for reference only"
  value       = aws_instance.cloudflared.public_ip
}
