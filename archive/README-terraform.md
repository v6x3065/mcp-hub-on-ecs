# ECS Remote MCP Hosting Platform

Host AWS MCP servers on ECS Fargate with path-based routing via ALB. Clients connect over HTTPS — no AWS credentials needed on client machines.

## Why Remote MCP?

Local MCP servers require AWS credentials on every client, making cross-account access, credential rotation, and cloud-based AI agent integration painful. This platform centralizes MCP hosting with IAM Task Roles, automatic credential management, and a single HTTPS endpoint for all services.

## Supported MCP Services

| Service | Transport | Description | PR |
|---------|-----------|-------------|----|
| **aws-api-mcp-server** | streamable-http | AWS CLI operations with cross-account support | [#2702](https://github.com/awslabs/mcp/pull/2702) |
| **aws-documentation-mcp-server** | streamable-http | AWS China documentation search | [#2247](https://github.com/awslabs/mcp/pull/2247) |

Both services use custom forks with HTTP transport support (`mengchencloud/mcp`: [`feat/cross-account-support`](https://github.com/mengchencloud/mcp/tree/feat/cross-account-support) and [`feature/aws-doc-streamable-http`](https://github.com/mengchencloud/mcp/tree/feature/aws-doc-streamable-http)). Once PRs merge, switch to official images via `terraform.tfvars`.

## Architecture

![Architecture Diagram](architecture.png)

- Clients → HTTPS → ALB (path-based routing) → ECS Fargate tasks in private subnets
- ECS Task Role → same-account AWS API calls + cross-account AssumeRole
- No credentials stored on client side

## Deployment with CloudFormation (`infra/`)

All AWS resources are defined as one-resource-per-stack CloudFormation templates under [infra/templates/](infra/templates), following the Lilly `Foundation/dev2` conventions (file name = stack name = resource name `lly-nw-cloudops-awsmcp…`, common `aws-mcp` tags, parameters with Defaults only, Outputs exported as `<StackName>:<Output>`). Standards: [infra/standards/](infra/standards); design: [docs/superpowers/specs/2026-11-22-aws-mcp-cfn-stacks-design.md](docs/superpowers/specs/2026-11-22-aws-mcp-cfn-stacks-design.md).

The central CI deploys changed templates in path order and stops on the first failure, so release **one layer per PR**, in this order:

| Layer | Stacks (prefix `lly-nw-cloudops-awsmcp`) |
|-------|-------------------------------------------|
| L1 | `-d-kms-01`, `-d-sm-01`, `-cf-d-pl-01` |
| L2 | `-alb-d-sg-01`, `-ecs-d-sg-01`, `-ecs-exec-d-iamp-01`, `-ecs-exec-d-iamr-01`, `-ecs-task-d-iamp-01`, `-ecs-task-d-iamr-01`, `-github-action-d-iamp-01`, `-github-action-d-iamr-01` |
| L3 | `-d-ecr-01`, `-d-ecr-02`, `-d-cwlg-01`, `-d-cwlg-02` |
| L4 | `-d-alb-01`, `-d-tg-01`, `-d-tg-02` |
| L5 | `-d-ecs-01`, `-d-ecssvc-01`, `-d-ecssvc-02` |
| Target accounts | `IAM/AWSMCP-TargetAccount/`: `-target-ro-d-iamp-01`, `-target-ro-d-iamr-01` (deployed in each queried account) |

Release an application version: run the **Build aws-mcp image** workflow (or `scripts/build-and-deploy-aws-*.sh`), then set `pImageTag` (and `pDesiredCount`, first release only) in the matching `ecssvc` template and open a PR. Fill the pilot values first: `pTargetAccountId` in `-ecs-task-d-iamp-01`, `pGitHubRepo` in `-github-action-d-iamr-01`, `pCertificateArn` / `pHttpsEnabled` if Cloudflare connects over HTTPS.

Local checks before a PR: `python3 infra/scripts/validate_standards.py` and `cfn-lint` / `cfn-guard` (same rules as the central validation).

> The Terraform below is the previous reference implementation. It is kept only for comparison and will be removed once the CloudFormation stacks are deployed.

## Quick Start

### Prerequisites

- AWS CLI configured
- Terraform >= 1.0 (AWS Provider >= 6.28)
- Docker
- Access to AWS China region (cn-northwest-1)

### Step 1: Configure

Copy and edit the example config:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Key settings in `terraform.tfvars`:

```hcl
deploy_aws_api = true
deploy_aws_doc = true

# HTTPS (optional)
enable_https    = true
certificate_arn = "arn:aws-cn:acm:cn-northwest-1:<account-id>:certificate/xxx"
```

**HTTPS prerequisites** (Terraform does not manage DNS or certificates):
1. Register a domain with valid ICP filing (备案) — required for China regions
2. Request or import a certificate in ACM (`aws acm request-certificate` or import via console)

If you don't have a certificate yet, set `enable_https = false` and use the [local proxy workaround](#testing-without-https) for testing.

### Step 2: Build Images

Build the fork images and push to ECR. The scripts automatically write the image URI to `terraform.tfvars`:

```bash
# Build aws-api (cross-account support fork)
./scripts/build-and-deploy-aws-api.sh

# Build aws-doc (streamable-http fork)
./scripts/build-and-deploy-aws-doc.sh
```

After PRs merge upstream, remove the `aws_api_image` / `aws_doc_image` lines from `terraform.tfvars` to use default official images.

Build options (environment variables): `REPO_URL` (default `https://github.com/mengchencloud/mcp.git`), `REF` (branch or tag), `REGION`. Images are built for `linux/amd64`, tagged `sha-<commit>`, and the ECR repository is created with scan-on-push if missing.

### Step 3: Enable Authentication (Optional)

Generate a bearer token and add it to `terraform.tfvars`:

```bash
TOKEN=$(openssl rand -base64 32)
echo "auth_token = \"${TOKEN}\"" >> terraform/terraform.tfvars
echo "Save this token for MCP client config: ${TOKEN}"
```

When `auth_token` is set, ALB rejects requests without a valid `Authorization` header (HTTP 401). Leave it empty or unset to disable authentication.

### Step 4: Deploy

```bash
cd terraform
terraform init
terraform apply
```

### Step 5: Configure DNS (HTTPS only)

Point your custom domain to the ALB:

```bash
cd terraform && terraform output alb_dns_name
```

Add a CNAME record in your DNS provider:

```
your-domain.com  CNAME  <alb-dns-name>
```

> China regions require a valid ICP filing (备案) for the domain.

### Step 6: ALB Access (Security Group)

The ALB only accepts traffic from the CIDRs in `alb_ingress_cidrs` (default: none, so the ALB is unreachable until you set it). Add the Cloudflare origin ranges and any test client IPs to `terraform.tfvars` and re-apply:

```hcl
alb_ingress_cidrs = ["203.0.113.10/32"]   # + Cloudflare origin ranges
```

> The rules are managed by Terraform; rules added manually in the console or CLI are removed on the next `apply`.

### Step 7: Configure MCP Client

```bash
terraform output mcp_endpoints
```

Example Kiro IDE config (`.kiro/settings/mcp.json`):

```json
{
  "mcpServers": {
    "aws-api-ecs-remote": {
      "url": "https://your-domain.com/aws-api/mcp",
      "headers": {
        "Accept": "application/json, text/event-stream",
        "Content-Type": "application/json",
        "Authorization": "Bearer <your-auth-token>"
      },
      "autoApprove": ["call_aws", "suggest_aws_commands"],
      "timeout": 120000
    },
    "aws-doc-ecs-remote": {
      "url": "https://your-domain.com/aws-doc/mcp",
      "headers": {
        "Accept": "application/json, text/event-stream",
        "Content-Type": "application/json",
        "Authorization": "Bearer <your-auth-token>"
      },
      "autoApprove": ["get_available_services", "read_documentation"],
      "timeout": 120000
    }
  }
}
```

ALB automatically rewrites paths: `https://domain.com/aws-api/mcp` → container `/mcp`.

### Testing Without HTTPS

StreamableHTTP requires HTTPS or localhost. Without a certificate, use a local proxy:

```bash
# Deploy with enable_https = false, then:
socat TCP-LISTEN:8003,fork,reuseaddr TCP:<alb-dns-name>:80
# Use http://127.0.0.1:8003/aws-api/mcp in MCP client config
```

### Test Connection

```bash
curl -X POST https://your-domain.com/aws-api/mcp \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <your-auth-token>" \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}},"id":1}'
```

## Cross-Account Support

The ECS task role can assume read-only roles in target accounts. The set of assumable roles is fixed in Terraform (`assume_role_target_arns`), so a caller-supplied `role_arn` outside that list is rejected by IAM.

### Usage

```python
call_aws(
  cli_command="aws s3api list-buckets --region cn-northwest-1",
  role_arn="arn:aws-cn:iam::<TARGET_ACCOUNT_ID>:role/McpCrossAccountReadOnly"
)
```

### Deploy Cross-Account Role

A CloudFormation template at `cfn/mcp-cross-account-role.yaml` creates a read-only role (AWS `ReadOnlyAccess` plus an explicit deny on data reads such as `s3:GetObject`, `secretsmanager:GetSecretValue`, `ssm:GetParameter*`, `dynamodb:GetItem/Query/Scan`) trusting the ECS task role. Optional parameters: `ExternalId` (adds an `sts:ExternalId` trust condition) and `MaxSessionDuration`.

Order matters because the trust policy needs the task role to exist:

1. `terraform apply` (creates the task role; no cross-account access yet)
2. Create the role in the target account(s) (below)
3. Set `assume_role_target_arns` in `terraform.tfvars` to the created role ARN(s) and `terraform apply` again

```bash
TASK_ROLE_ARN=$(cd terraform && terraform output -raw task_role_arn)

# Single account
aws cloudformation create-stack \
  --stack-name mcp-cross-account-role \
  --template-body file://cfn/mcp-cross-account-role.yaml \
  --parameters ParameterKey=McpTaskRoleArn,ParameterValue=$TASK_ROLE_ARN \
  --capabilities CAPABILITY_NAMED_IAM

# Or batch via StackSets (requires AWS Organizations)
aws cloudformation create-stack-set \
  --stack-set-name mcp-cross-account-role \
  --template-body file://cfn/mcp-cross-account-role.yaml \
  --parameters ParameterKey=McpTaskRoleArn,ParameterValue=$TASK_ROLE_ARN \
  --capabilities CAPABILITY_NAMED_IAM \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
  --region cn-northwest-1
```

### Account allow-list (server side)

`aws_api_account_allowlist` passes an alias → role map to the server as `AWS_API_MCP_ACCOUNT_ALLOWLIST`. It only takes effect with a fork build that implements it; stock images ignore it, and IAM scoping above remains the enforced control.

## Cost Estimation (cn-northwest-1, CNY)

| Component | 1 service | 2 services |
|-----------|-----------|------------|
| ECS Fargate (0.5 vCPU + 1GB) | ¥111 | ¥223 |
| NAT Gateway + data | ¥289 | ¥307 |
| ALB + LCU | ¥166 | ¥166 |
| CloudWatch Logs | ¥2 | ¥5 |
| **Total** | **~¥569/mo** | **~¥701/mo** |

Tips: disable unused services, use Fargate Spot for non-prod, reduce log retention.

## Security

- ECS tasks in private subnets, no direct internet access
- ALB inbound restricted to `alb_ingress_cidrs` (Cloudflare ranges / test IPs); empty by default
- **Bearer token authentication** — optional, set `auth_token` in `terraform.tfvars` to enable. ALB rejects requests without a valid `Authorization` header (401). Supports both `Bearer <token>` and raw `<token>` formats. Generate a token with `openssl rand -base64 32`
- Optional server-side JWT validation (`mcp_auth_type = "oauth"` with `mcp_auth_issuer` / `mcp_auth_jwks_uri`, e.g. Entra ID)
- aws-api runs with `READ_OPERATIONS_ONLY=true` and telemetry disabled
- Task role: `sts:AssumeRole` only on `assume_role_target_arns`, explicit deny on data-plane reads; no `ReadOnlyAccess` unless `attach_same_account_readonly = true`
- HTTPS with ACM certificates (optional)
- No AWS credentials on client machines

## Cleanup

```bash
cd terraform && terraform destroy
```

## License

Apache-2.0
