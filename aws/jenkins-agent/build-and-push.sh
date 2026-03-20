#!/bin/bash
set -e

ACCOUNT_ID="249297038289"
REGION="us-east-1"
REPO_NAME="jenkins-agent"
IMAGE_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest"

echo "==> Creating ECR repository (if not exists)..."
aws ecr describe-repositories --repository-names $REPO_NAME --region $REGION 2>/dev/null || \
  aws ecr create-repository --repository-name $REPO_NAME --region $REGION

echo "==> Logging into ECR..."
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

echo "==> Building image..."
docker build -t $REPO_NAME .

echo "==> Tagging image..."
docker tag $REPO_NAME:latest $IMAGE_URI

echo "==> Pushing to ECR..."
docker push $IMAGE_URI

echo ""
echo "Done! Use this image in Jenkins agent template:"
echo "$IMAGE_URI"
