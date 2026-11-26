# aws-mcp: Remote MCP servers on ECS Fargate (AWS China)

Hosts two read-only MCP servers for CloudOps AI (Copilot Studio / Power Automate) in private subnets of the dev2 account (`cn-northwest-1`). A single public entry, `https://clade.dev.lilly.cn/mcp`, goes through Cloudflare to an internet-facing ALB, which validates the Entra ID access token (`jwt-validation`: iss, exp, aud, scp) and forwards to an MCP gateway. The gateway reaches the two backends over ECS Service Connect; the backends have no ALB and only accept traffic from the gateway security group.

| Service | Reached as | Purpose |
|---------|------------|---------|
| mcp-gateway (`ecssvc-00`) | `/mcp` (public) | Merges the tools of both backends (`aws_api_*`, `aws_doc_*`) and writes the caller to the audit log. Code: [mcp-gateway/](mcp-gateway) |
| aws-api (`ecssvc-01`) | `http://aws-api:8000/mcp` (internal) | Read-only AWS CLI queries with cross-account `AssumeRole` ([fork `feat/cross-account-support`](https://github.com/mengchencloud/mcp/tree/feat/cross-account-support)) |
| aws-doc (`ecssvc-02`) | `http://aws-doc:8000/mcp` (internal) | AWS China documentation search ([fork `feature/aws-doc-streamable-http`](https://github.com/mengchencloud/mcp/tree/feature/aws-doc-streamable-http)) |

Everything is deployed as CloudFormation stacks (one resource per stack) through the central Lilly CI. Design and decisions: [docs/superpowers/specs/2026-11-22-aws-mcp-cfn-stacks-design.md](docs/superpowers/specs/2026-11-22-aws-mcp-cfn-stacks-design.md).

## Repository layout

```
config.yml         # CI account / role / region (dev2)
templates/         # stacks: templates/<Type>/<App>/<stack-name>.yaml
standards/         # tags.yaml (single source of tag values), naming.md
scripts/           # validate_standards.py
mcp-gateway/       # MCP gateway code and Dockerfile (image built by the workflow)
.github/workflows/ # build-image.yml (build and push MCP server images to ECR)
docs/              # design documents
archive/           # previous Terraform implementation and design material, not deployed
```

Conventions ([standards/naming.md](standards/naming.md)): file name = stack name = resource name `lly-nw-cloudops-awsmcp[-role]-d-<type>-NN`; common `aws-mcp` tags; parameters carry Defaults only (the CI deploys with Defaults and turns empty ones into `default_placeholder`, so use `NA`); every Output is exported as `<StackName>:<Output>` and consumers import it through a `pXxxStackName` parameter.

## Release order

The central CI deploys changed templates in path order and stops on the first failure: release **one layer per PR**, in this order.

| Layer | Stacks (prefix `lly-nw-cloudops-awsmcp`) |
|-------|-------------------------------------------|
| L1 | `-d-kms-01`, `-d-sm-01`, `-cf-d-pl-01` |
| L2 | `-alb-d-sg-01`, `-gw-d-sg-01`, `-ecs-d-sg-01`, `-ecs-exec-d-iamp-01`, `-ecs-exec-d-iamr-01`, `-ecs-task-d-iamp-01`, `-ecs-task-d-iamr-01`, `-github-action-d-iamp-01`, `-github-action-d-iamr-01` |
| L3 | `-d-ecr-00`, `-d-ecr-01`, `-d-ecr-02`, `-d-cwlg-00`, `-d-cwlg-01`, `-d-cwlg-02` |
| L4 | `-d-alb-01`, `-d-tg-00` |
| L5 | `-d-ecs-01`, `-d-ecssvc-01`, `-d-ecssvc-02`, `-d-ecssvc-00` |
| Target accounts | `templates/IAM/AWSMCP-TargetAccount/`: `-target-ro-d-iamp-01`, `-target-ro-d-iamr-01` (deployed in each queried account, not in dev2) |

## Releasing an application version

1. Run the **Build aws-mcp image** workflow (`aws-api`, `aws-doc` or `mcp-gateway`; fork ref for the first two). It builds linux/amd64, pushes `sha-<commit>` to the ECR repository and prints the tag. The gateway build runs a `/healthz` smoke test first.
2. Set `pImageTag` (and `pDesiredCount`, first release only) in the matching `templates/ECS/AWSMCP/…-d-ecssvc-0N.yaml` and open a PR.

## Values to fill before the first real deployment

- `pTargetAccountId` in `-ecs-task-d-iamp-01` (pilot target account; `NA` = no cross-account access)
- `pGitHubRepo` in `-github-action-d-iamr-01` is `BUIT_CN_awsmcp_AWS` (organization `EliLillyCo`)
- `pCertificateArn` in `-d-alb-01` (set to the `*.dev.lilly.cn` ACM certificate); the ALB only has an HTTPS (443) listener
- `pSNOWRequestIdTag` in every template (via `standards/tags.yaml`), currently `CHG3151871`

## Local checks before a PR

```bash
python3 scripts/validate_standards.py        # naming, tags, Defaults, Exports/ImportValues, boundary
cfn-lint --config-file <central>/security/.cfnlintrc templates/<path>.yaml
```

The central PR validation also runs `cfn-guard` rules for IAM roles, KMS keys and security groups.

## Client configuration

```json
{
  "mcpServers": {
    "aws-api-ecs-remote": {
      "url": "https://<cloudflare-domain>/aws-api/mcp",
      "headers": {
        "Accept": "application/json, text/event-stream",
        "Authorization": "Bearer <token from secret lly-nw-cloudops-awsmcp-d-sm-01>"
      }
    },
    "aws-doc-ecs-remote": {
      "url": "https://<cloudflare-domain>/aws-doc/mcp",
      "headers": {
        "Accept": "application/json, text/event-stream",
        "Authorization": "Bearer <token from secret lly-nw-cloudops-awsmcp-d-sm-01>"
      }
    }
  }
}
```

The ALB strips the `/aws-api` or `/aws-doc` prefix before forwarding to the container.

## Archive

[archive/](archive) keeps the earlier Terraform implementation, its README ([archive/README-terraform.md](archive/README-terraform.md)), the Lilly generic templates used as reference, and the architecture material. None of it is deployed.

## License

Apache-2.0
