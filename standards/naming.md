# Naming standard

```
lly-nw-cloudops-awsmcp[-<role>]-d-<type>-<NN>
```

- File name (without `.yaml`) = CloudFormation stack name = name of the stack's primary resource.
- `d` = DEV (`q`/`p` for other environments, produced by copying to the matching branch).
- `<role>` separates resources of different roles (`alb`, `ecs`, `ecs-exec`, `ecs-task`, `cf`, `github-action`, `target-ro`).
- `<NN>` separates instances of the same kind: `01` = aws-api, `02` = aws-doc.
- No spaces anywhere in paths or names (the central CI mangles them).
- Never name a stack `China*` (blocked by `IAM-China-Boundary` GuardCFNStacks).

| Type | Resource | Notes |
|------|----------|-------|
| `kms` | KMS key + alias | alias = `alias/<name>` |
| `sm` | Secrets Manager secret | |
| `pl` | Managed prefix list | |
| `sg` | Security group | |
| `iamp` | IAM managed policy | |
| `iamr` | IAM role | always with `IAM-China-Boundary` |
| `ecr` | ECR repository | |
| `cwlg` | CloudWatch log group | log group name = `/aws/ecs/<name>` (existing dev2 convention) |
| `alb` | Application load balancer | name limit 32 |
| `tg` | Target group (+ listener rule) | name limit 32 |
| `ecs` | ECS cluster | |
| `ecssvc` | ECS task definition + service | |

Cross-stack references: every Output is exported as `<StackName>:<OutputName>`; consumers take the
upstream stack name as a parameter (`pXxxStackName`, Default = upstream file name) and use
`Fn::ImportValue: !Sub '${pXxxStackName}:<OutputName>'`.

CI constraint: parameters must never have an empty Default (the CI replaces empty values with
`default_placeholder`). Use `NA` for "not set" and drive behaviour with Conditions.
