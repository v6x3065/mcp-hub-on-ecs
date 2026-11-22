#!/bin/bash
# Build aws-documentation-mcp-server with streamable-http support and push to ECR
# Source: mengchencloud/mcp@feature/aws-doc-streamable-http (override with REPO_URL / REF)
# Usage: ./scripts/build-and-deploy-aws-doc.sh
set -euo pipefail

# shellcheck source=lib/build-image.sh
source "$(dirname "$0")/lib/build-image.sh"

build_and_push src/aws-documentation-mcp-server lly-nw-cloudops-awsmcp-d-ecr-02 lly-nw-cloudops-awsmcp-d-ecssvc-02 feature/aws-doc-streamable-http
