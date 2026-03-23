# =============================================================================
# STORAGE MODULE — MAIN
# Creates: S3 media bucket + ECR repositories
#
# CONCEPT: lifecycle
# This module demonstrates two lifecycle rules:
#
# 1. ignore_changes on S3 — Saleor uploads files to S3 constantly.
#    If we don't ignore those changes, every `terraform plan` would show
#    thousands of "drift" changes. We tell Terraform: "don't touch objects
#    inside the bucket, just manage the bucket configuration itself."
#
# 2. for_each on ECR — create multiple repos from a single resource block
# =============================================================================

# -----------------------------------------------------------------------------
# S3 MEDIA BUCKET
# Stores product images, user uploads, thumbnails
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "media" {
  bucket = "${var.app_name}-media-${var.environment}-learnwithvinay"

  # CONCEPT: lifecycle
  # ignore_changes tells Terraform: "even if these attributes change outside
  # of Terraform, don't report them as drift, don't try to fix them."
  #
  # Why we use it here:
  # - Saleor continuously uploads product images into this bucket
  # - Without ignore_changes, every `terraform plan` would show those
  #   uploads as "unexpected changes"
  # - We only want Terraform to manage the BUCKET SETTINGS (versioning,
  #   encryption, etc.) — not the actual files inside
  lifecycle {
    ignore_changes = [
      tags,         # tags might be modified by other tools
    ]
    # Note: we don't set prevent_destroy here because media bucket
    # can be recreated (populatedb re-uploads everything)
  }

  tags = {
    Name        = "${var.app_name}-media-${var.environment}"
    Environment = var.environment
  }
}

# Allow public access — media files (product images) must be publicly readable
# Saleor sets ACL=public-read on each uploaded object so browsers can load images
resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Enable ACLs — Saleor calls PutObjectAcl to make each image publicly readable.
# New S3 buckets default to ACLs disabled (BucketOwnerEnforced) since Apr 2023.
# We switch to BucketOwnerPreferred so ACLs work while the bucket owner retains control.
resource "aws_s3_bucket_ownership_controls" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }

  depends_on = [aws_s3_bucket_public_access_block.media]
}

# Bucket policy — allow anyone to GET objects (read product images)
resource "aws_s3_bucket_policy" "media_public_read" {
  bucket = aws_s3_bucket.media.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.media.arn}/*"
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.media]
}

# Versioning off for media — no need to keep old versions of product images
resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id

  versioning_configuration {
    status = "Suspended"
  }
}

# Encrypt media at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CORS policy — allows the Saleor frontend to upload files directly to S3
resource "aws_s3_bucket_cors_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

# -----------------------------------------------------------------------------
# ECR REPOSITORIES
# CONCEPT: for_each
# Instead of writing one resource block per repo, we loop over the list.
# each.key = the repo name ("saleor-backend", "saleor-dashboard", etc.)
#
# for_each vs count:
# - count uses index numbers (0, 1, 2) — fragile if you reorder the list
# - for_each uses the actual value as a key — safer, more readable
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "this" {
  for_each = toset(var.ecr_repo_names)
  # toset() converts the list to a set — for_each requires a set or map

  name                 = each.key
  image_tag_mutability = "MUTABLE"  # allows overwriting "latest" tag

  image_scanning_configuration {
    scan_on_push = true  # automatically scan for vulnerabilities on every push
  }

  # CONCEPT: lifecycle
  # prevent_destroy = false for ECR — images can be rebuilt by CI/CD
  # create_before_destroy = true — if repo needs to be replaced, create
  # the new one before deleting the old one (zero downtime)
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = each.key
    Environment = var.environment
  }
}

# ECR lifecycle policy — automatically delete old images to save storage costs
# Keeps only the last 10 images per repo
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
