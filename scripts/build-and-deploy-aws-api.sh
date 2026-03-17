#!/bin/bash
# Build aws-api-mcp-server with cross-account support and push to ECR
# Fork PR: https://github.com/awslabs/mcp/pull/2702
# Usage: ./scripts/build-and-deploy-aws-api.sh
set -e

REGION="cn-northwest-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com.cn/aws-api-mcp-server"
IMAGE_TAG="cross-account"
TFVARS="$(cd "$(dirname "$0")/../terraform" && pwd)/terraform.tfvars"

TMPDIR=$(mktemp -d); trap "rm -rf $TMPDIR" EXIT

echo "==> Cloning fork (feat/cross-account-support)..."
git clone -b feat/cross-account-support --depth 1 https://github.com/mengchen-tam/mcp.git "$TMPDIR/mcp"

echo "==> Building image..."
docker build -t aws-api-mcp-server:${IMAGE_TAG} "$TMPDIR/mcp/src/aws-api-mcp-server"

echo "==> Pushing to ECR..."
aws ecr get-login-password --region $REGION | \
    docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com.cn
docker tag aws-api-mcp-server:${IMAGE_TAG} ${ECR_REPO}:${IMAGE_TAG}
docker push ${ECR_REPO}:${IMAGE_TAG}

IMAGE_URI="${ECR_REPO}:${IMAGE_TAG}"
echo "==> Updating terraform.tfvars..."
if grep -q '^aws_api_image' "$TFVARS" 2>/dev/null; then
    sed -i "s|^aws_api_image.*|aws_api_image = \"${IMAGE_URI}\"|" "$TFVARS"
else
    echo "" >> "$TFVARS"
    echo "aws_api_image = \"${IMAGE_URI}\"" >> "$TFVARS"
fi

echo "✅ Done: ${IMAGE_URI}"
echo "Run 'cd terraform && terraform apply' to deploy."
