# =============================================================================
# LOAD BALANCER MODULE — OUTPUTS
# =============================================================================

output "alb_arn" {
  description = "ARN of the ALB — needed to attach ECS services"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB — used for Route53 record"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB — needed for Route53 alias record"
  value       = aws_lb.this.zone_id
}

output "alb_security_group_id" {
  description = "Security group ID of the ALB — ECS tasks allow traffic from this"
  value       = aws_security_group.alb.id
}

output "target_group_arns" {
  description = "Map of target group name → ARN. Used by ECS services."
  value       = { for name, tg in aws_lb_target_group.this : name => tg.arn }
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener"
  value       = aws_lb_listener.https.arn
}

output "certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = aws_acm_certificate.this.arn
}

output "certificate_domain_validation_options" {
  description = "DNS validation records needed for ACM — used to create Route53 records"
  value       = aws_acm_certificate.this.domain_validation_options
}
