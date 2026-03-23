# =============================================================================
# STORAGE MODULE — OUTPUTS
# =============================================================================

output "media_bucket_name" {
  description = "Name of the S3 media bucket"
  value       = aws_s3_bucket.media.bucket
}

output "media_bucket_arn" {
  description = "ARN of the S3 media bucket — needed by IAM module"
  value       = aws_s3_bucket.media.arn
}

output "ecr_repository_urls" {
  description = "Map of ECR repository name → URL. Used by ECS task definitions."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
  # Result looks like:
  # {
  #   "saleor-backend"    = "249297038289.dkr.ecr.us-east-1.amazonaws.com/saleor-backend"
  #   "saleor-dashboard"  = "249297038289.dkr.ecr.us-east-1.amazonaws.com/saleor-dashboard"
  #   "saleor-storefront" = "249297038289.dkr.ecr.us-east-1.amazonaws.com/saleor-storefront"
  # }
}
