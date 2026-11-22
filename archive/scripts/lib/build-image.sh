#!/bin/bash
# Shared helper for build-and-deploy-*.sh (source this file, do not run it).
# Emergency/local alternative to .github/workflows/build-image.yml.
#
# The ECR repositories are owned by the infra stacks (infra/templates/ECR/AWSMCP), so this
# only builds and pushes. Release = set pImageTag in the matching ecssvc template and open a PR.
#
# Environment overrides:
#   REPO_URL  fork to clone     (default: https://github.com/mengchencloud/mcp.git)
#   REF       branch or tag     (default: passed in by the calling script)
#   REGION    ECR/ECS region    (default: cn-northwest-1)
#   CONTAINER_CLI  docker|podman (default: docker)

# build_and_push <src_subdir> <ecr_repo_name> <ecssvc_template> <default_ref>
# Builds a linux/amd64 image (matches the Fargate runtime platform) tagged with the cloned
# commit SHA and pushes it to ECR.
build_and_push() {
    local src_subdir="$1" repo_name="$2" ecssvc="$3" default_ref="$4"

    local region="${REGION:-cn-northwest-1}"
    local repo_url="${REPO_URL:-https://github.com/mengchencloud/mcp.git}"
    local ref="${REF:-$default_ref}"
    local cli="${CONTAINER_CLI:-docker}"

    local account_id registry workdir sha image_tag image_uri
    account_id=$(aws sts get-caller-identity --query Account --output text)
    registry="${account_id}.dkr.ecr.${region}.amazonaws.com.cn"

    aws ecr describe-repositories --repository-names "$repo_name" --region "$region" >/dev/null ||
        { echo "ECR repository ${repo_name} not found: deploy the ECR stack first (infra/templates/ECR/AWSMCP)"; return 1; }

    workdir=$(mktemp -d)
    trap "rm -rf '$workdir'" EXIT

    echo "==> Cloning ${repo_url} (${ref})..."
    git clone -b "$ref" --depth 1 "$repo_url" "$workdir/mcp"
    sha=$(git -C "$workdir/mcp" rev-parse --short=12 HEAD)
    image_tag="sha-${sha}"
    image_uri="${registry}/${repo_name}:${image_tag}"

    echo "==> Building ${repo_name}:${image_tag} (linux/amd64)..."
    "$cli" build --platform linux/amd64 -t "$image_uri" "$workdir/mcp/${src_subdir}"

    echo "==> Pushing to ECR..."
    aws ecr get-login-password --region "$region" |
        "$cli" login --username AWS --password-stdin "$registry"
    "$cli" push "$image_uri"

    echo "✅ Done: ${image_uri} (source ${repo_url} @ ${ref}, commit ${sha})"
    echo "Release: set pImageTag to '${image_tag}' in infra/templates/ECS/AWSMCP/${ecssvc}.yaml and open a PR."
}
