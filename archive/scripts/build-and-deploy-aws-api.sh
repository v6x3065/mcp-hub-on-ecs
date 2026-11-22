#!/bin/bash
# Build aws-api-mcp-server with cross-account support and push to ECR
# Source: mengchencloud/mcp@feat/cross-account-support (override with REPO_URL / REF)
# Usage: ./scripts/build-and-deploy-aws-api.sh
set -euo pipefail

# shellcheck source=lib/build-image.sh
source "$(dirname "$0")/lib/build-image.sh"

build_and_push src/aws-api-mcp-server lly-nw-cloudops-awsmcp-d-ecr-01 lly-nw-cloudops-awsmcp-d-ecssvc-01 feat/cross-account-support
