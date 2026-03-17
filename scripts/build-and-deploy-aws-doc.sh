#!/bin/bash
# Build aws-documentation-mcp-server with streamable-http support and push to ECR
# Fork PR: https://github.com/awslabs/mcp/pull/2247
# Usage: ./scripts/build-and-deploy-aws-doc.sh
set -e

REGION="cn-northwest-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com.cn/aws-documentation-mcp-server-http"
IMAGE_TAG="latest"
TFVARS="$(cd "$(dirname "$0")/../terraform" && pwd)/terraform.tfvars"

TMPDIR=$(mktemp -d); trap "rm -rf $TMPDIR" EXIT

echo "==> Cloning fork (feature/aws-doc-streamable-http)..."
git clone -b feature/aws-doc-streamable-http --depth 1 https://github.com/mengchen-tam/mcp.git "$TMPDIR/mcp"

echo "==> Building image..."
docker build -t aws-doc-http:${IMAGE_TAG} "$TMPDIR/mcp/src/aws-documentation-mcp-server"

echo "==> Pushing to ECR..."
aws ecr get-login-password --region $REGION | \
    docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com.cn
docker tag aws-doc-http:${IMAGE_TAG} ${ECR_REPO}:${IMAGE_TAG}
docker push ${ECR_REPO}:${IMAGE_TAG}

IMAGE_URI="${ECR_REPO}:${IMAGE_TAG}"
echo "==> Updating terraform.tfvars..."
if grep -q '^aws_doc_image' "$TFVARS" 2>/dev/null; then
    sed -i "s|^aws_doc_image.*|aws_doc_image = \"${IMAGE_URI}\"|" "$TFVARS"
else
    echo "" >> "$TFVARS"
    echo "aws_doc_image = \"${IMAGE_URI}\"" >> "$TFVARS"
fi

echo "✅ Done: ${IMAGE_URI}"
echo "Run 'cd terraform && terraform apply' to deploy."
