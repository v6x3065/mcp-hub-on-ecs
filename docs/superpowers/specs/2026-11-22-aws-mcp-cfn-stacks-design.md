# aws-mcp CloudFormation 堆栈结构与标准定义

状态：**设计已确认，待启动开发**（不含部署）
适用：AWS 中国 `cn-northwest-1`，dev2 账号，环境字母 `d`（DEV）

已确认决策：命名前缀 `lly-nw-cloudops-awsmcp`；复用已有 VPC/子网；CFN 代码放在仓库根目录 `templates/`（已去掉 `infra/` 层，旧内容归档到 `archive/`）；模板开发完成后**拷贝 `templates/` 到 `Foundation/dev2` 分支**由中央 CI 部署；类型缩写（`ecr/cwlg/alb/tg/ecs/ecssvc/pl`）接受；标签值按 §4 建议值。`terraform/` 先保留作对照，CFN 完成后删除。

## 1. 目标

把 `mcp-hub-on-ecs` 里原本由 Terraform 管理的所有 AWS 资源，拆成**一个资源一个 CloudFormation 堆栈**（一个 yaml），按 Lilly 参考项目（`LCDT_DevSecOps_DEV/Foundation/dev2`）的结构和命名标准组织，可直接交给参考项目的 CI 部署。

不变的范围边界：VPC/子网/NAT、`IAM-China-Boundary`、域名/证书/DNS（Cloudflare 团队）、CI 角色，均为**已有前置条件**，只做参数引用，不创建。

## 2. 从参考项目和 CI 得到的硬约束

这些约束来自 `deploy_stack.py` 和中央 `deploy.yml`，是标准的依据：

| # | 约束 | 对标准的影响 |
|---|------|--------------|
| C1 | 堆栈名 = `basename(文件名, .yaml)`，空格会被替换成下划线 | 文件名即堆栈名，路径和文件名**禁止空格** |
| C2 | CI 只用模板里每个参数的 **Default** 值部署，不接收外部参数 | 所有环境差异都写在 Default 里；改配置 = 改 Default 提 PR |
| C3 | 参数 Default 为空时，CI 会替换成字符串 `default_placeholder` | **禁止空 Default**；“可选”用哨兵值 `NA` + Condition |
| C4 | CI 带 `CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND` | 允许命名 IAM 资源 |
| C5 | CI 按 `changed_files.txt` 顺序逐个部署，**任一失败即终止** | 依赖顺序必须由“分层发布”保证（见 §7） |
| C6 | 一个分支对应一个账号（`config.yml`：role / region / s3Bucket） | 环境靠分支区分，模板内的 `-d-` 在 q/p 分支复制时替换 |
| C7 | 所有 IAM Role 带 `PermissionsBoundary: arn:aws-cn:iam::<account>:policy/IAM-China-Boundary` | 所有 Role 模板必带；task role 所需动作必须在 Boundary 允许范围内（待核对） |
| C8 | cfn-guard：日志组必须 KMS 加密且设置保留期；S3 必须加密/禁公网等 | 日志组、ECR 使用本项目 CMK；保留期为参数 |

## 3. 命名规范

```
lly-nw-cloudops-awsmcp[-<角色>]-d-<类型>-<NN>
```

- 前缀 `lly-nw-cloudops-awsmcp` 固定；`d` = DEV；`NN` = 实例序号
- **文件名 = 堆栈名 = 该堆栈主资源名**（参数 `pXxxName` 的 Default 就等于文件名去掉 `.yaml`）
- 一个堆栈只放一个“有名字的主资源”，其依附资源（监听器规则、别名、策略附件）不单独起名
- 角色不同的资源，用“角色”区分，放在前缀后（沿用参考项目，如 `...aifoundation-alb-d-sg-01`）：`alb`、`ecs`、`ecs-exec`、`ecs-task`
- 同类的多个 MCP 服务实例，用序号区分：**`01` = aws-api，`02` = aws-doc**（TG、ALB 名称上限 32 字符，加组件名会超长，所以统一用序号）

类型缩写（沿用参考项目的已有缩写；标 ★ 的是参考项目里没有的，需确认）：

| 缩写 | 资源 | 缩写 | 资源 |
|------|------|------|------|
| `kms` | KMS Key + Alias | `sm` | Secrets Manager |
| `sg` | Security Group | `pl` ★ | Managed Prefix List |
| `iamp` | IAM Managed Policy | `iamr` | IAM Role |
| `ecr` ★ | ECR Repository | `cwlg` ★ | CloudWatch Log Group |
| `alb` ★ | Application Load Balancer | `tg` ★ | Target Group（含路由规则） |
| `ecs` ★ | ECS Cluster | `ecssvc` ★ | ECS Task Definition + Service |

长度校验（已核对）：ALB 31 / TG 30 / 日志组 32 / ECS 服务 34 / IAM Role 最长 42（上限 64）/ SG 34，均在各自上限内。

## 4. 标签标准（所有堆栈完全一致）

每个模板都带下面 13 个标签参数（沿用参考项目的参数名和 Key 名），Default 一致；每个资源另加 `Name` 标签 = 文件名。

| 参数 | Tag Key | Default | 来源/状态 |
|------|---------|---------|-----------|
| pApplNameTag | ApplName | `aws-mcp` | 你指定 |
| pAdminTeamTag | AdminTeam | `GISS` | 参考项目固定值 |
| pApplicationCiTag | ApplicationCi | `CI00000000000000` | 你指定“全 0” |
| pPrimaryItContactTag | PrimaryItContact | `cn_it_infra_cloud_ops@lists.lilly.com` | 参考项目固定值 |
| pSNOWRequestIdTag | SNOWRequestId | `NA` | ⚠ 待确认（无 CHG 号） |
| pSystemOwnerTag | SystemOwner | `xu_ming_ming@lilly.com` | 你指定 |
| pSystemCustodianTag | SystemCustodian | `shen_jun_jack@lilly.com` | 你指定 |
| pCostCenterTag | CostCenter | `5205060` | ⚠ 待确认（CloudOps 自有项目 cloudpos 使用此值） |
| pMLPSTag | MLPS | `No` | ⚠ 待确认 |
| pEnvironmentTag | Environment | `DEV` | 参考项目 |
| pDataClassificationTag | DataClassification | `Yellow` | ⚠ 待确认（资源配置/日志数据，建议 Yellow） |
| pBusinessAreaTag | BusinessArea | `Commercial` | CloudOps 自有项目同值 |
| pLevel1BusinessAreaTag | Level1BusinessArea | `IBU` | CloudOps 自有项目同值 |

一致性由校验脚本保证（见 §8），标签值的唯一来源是 `standards/tags.yaml`，不手工维护。

头部 `pDeveloper` / `pReviewer` 的 Default：`Jack.Shen` / `Simon.Xu`（沿用参考项目 AllowedValues 清单中的人员；Simon.Xu 是参考项目 CODEOWNER，可随时改）。

## 5. 模板标准

1. **头部注释块**沿用参考项目：`CR` / `Change request purpose` / `Developer` / `Reviewer`；参数 `pDeveloper` / `pReviewer`（沿用 AllowedValues 人员清单）
2. `Metadata.AWS::CloudFormation::Interface` 分组：资源参数 / 依赖（上游堆栈）/ 标签 / Developer & Reviewer
3. **参数命名**：`p` + PascalCase；资源名参数 `pXxxName`，Default = 文件名；逻辑资源 ID 以 `r` 开头；输出 ID PascalCase
4. **参数类型**：尽量用 AWS 专用类型（`AWS::EC2::VPC::Id`、`List<AWS::EC2::Subnet::Id>` 等）；数值用 `Number` 并带范围
5. **禁止项**：空 Default（C3）、写死账号 ID/分区/区域（改用 `${AWS::AccountId}` / `${AWS::Partition}` / `${AWS::Region}`）、任何明文密钥
6. **可选项**：参数 Default 用 `NA`，用 Condition 控制（如无证书则不建 443 监听）
7. 所有 IAM Role 带 Boundary（C7）；Role 的权限用独立的 `iamp` 堆栈（ManagedPolicy）承载，Role 堆栈只做挂载
8. 资源保护：日志组、ECR、KMS 设 `DeletionPolicy: Retain`（KMS/日志同时保留 `UpdateReplacePolicy`）

## 6. 堆栈间依赖与 Output 标准

因为 CI 只读 Default（C2），跨堆栈引用统一用 **Export / ImportValue**，并保持参数化：

- 每个堆栈的 `Outputs` 都带 `Export`，导出名固定为 `<堆栈名>:<输出名>`
- 消费方有一个参数 `pXxxStackName`，Default = 上游堆栈名（即上游文件名）；引用方式：
  `Fn::ImportValue: !Sub '${pXxxStackName}:SecurityGroupId'`
- 所以**上下游堆栈改名时，只需改消费方的一个 Default**
- 跨账号（目标账号角色）无法 ImportValue，用参数计算 ARN（见 §9）
- 每个堆栈还输出 `StackContact`（= pDeveloper），沿用参考项目

## 7. 堆栈清单、依赖与发布分层

目录沿用参考项目的 `templates/<类型>/<应用>/`，放在本仓库根目录，应用目录名 `AWSMCP`；下表目录均相对于 `templates/`。

| 层 | 堆栈（文件名即堆栈名，省略共同前缀 `lly-nw-cloudops-awsmcp`） | 目录 | 导入 | 导出 |
|----|----|----|----|----|
| L1 | `-d-kms-01` | `KMS/AWSMCP/` | — | KeyArn, KeyId, AliasName |
| L1 | `-d-sm-01`（ALB 共享令牌，自动生成） | `Secrets_Manager/AWSMCP/` | kms-01 | SecretArn |
| L1 | `-cf-d-pl-01`（Cloudflare 回源网段） | `Security_Group/AWSMCP/` | — | PrefixListId |
| L2 | `-alb-d-sg-01` | `Security_Group/AWSMCP/` | pl-01 | SecurityGroupId |
| L2 | `-ecs-d-sg-01` | `Security_Group/AWSMCP/` | alb-d-sg-01 | SecurityGroupId |
| L2 | `-ecs-exec-d-iamp-01` | `IAM/AWSMCP/` | kms-01 | PolicyArn |
| L2 | `-ecs-task-d-iamp-01` | `IAM/AWSMCP/` | — | PolicyArn |
| L2 | `-ecs-exec-d-iamr-01` | `IAM/AWSMCP/` | ecs-exec-iamp | RoleArn |
| L2 | `-ecs-task-d-iamr-01` | `IAM/AWSMCP/` | ecs-task-iamp | RoleArn, RoleName |
| L2 | `-github-action-d-iamp-01`（镜像推送权限：仅限本项目 ECR 仓库前缀）、`-github-action-d-iamr-01`（GitHub OIDC 角色，信任 `repo:<org>/<repo>:*`） | `IAM/AWSMCP/` | — | RoleArn |
| L3 | `-d-ecr-01`（aws-api）、`-d-ecr-02`（aws-doc） | `ECR/AWSMCP/` | kms-01 | RepositoryUri, RepositoryArn |
| L3 | `-d-cwlg-01`、`-d-cwlg-02` | `CloudWatch_Logs/AWSMCP/` | kms-01 | LogGroupName, LogGroupArn |
| L4 | `-d-alb-01`（ALB + 80/443 监听器） | `ALB/AWSMCP/` | alb-d-sg-01 | LoadBalancerArn, DnsName, HostedZoneId, HttpListenerArn, HttpsListenerArn |
| L4 | `-d-tg-01`（aws-api）、`-d-tg-02`（aws-doc）：TG + 路径规则 + 路径改写 + 令牌校验 | `ALB/AWSMCP/` | alb-01, sm-01 | TargetGroupArn |
| L5 | `-d-ecs-01`（集群） | `ECS/AWSMCP/` | — | ClusterArn, ClusterName |
| L5 | `-d-ecssvc-01`、`-d-ecssvc-02`：任务定义 + 服务 | `ECS/AWSMCP/` | ecs-01, ecs-exec/task-iamr, ecs-d-sg-01, tg, ecr, cwlg | ServiceName |
| 目标账号 | `-target-ro-d-iamr-01`、`-target-ro-d-iamp-01` | `IAM/AWSMCP-TargetAccount/` | 无（见 §9） | RoleArn |

说明：

- **ecs-exec-iamp / ecs-task-iamp 对 ECR、日志组使用名称前缀通配**（`lly-nw-cloudops-awsmcp-*`），不导入它们的 ARN，这样 IAM 层不依赖 L3
- 镜像：`ecssvc` 导入 ECR 的 `RepositoryUri`，再拼 `pImageTag`；发布新镜像 = 改 `pImageTag` 的 Default 提 PR
- 层内也有少量先后关系（如 `iamp` → `iamr`、`alb-d-sg` → `ecs-d-sg`），已核对在中央 CI 的路径字母序下天然满足（`…-iamp-01` < `…-iamr-01`，`alb` < `ecs`）；**层与层之间必须分 PR 先后发布**

**发布顺序（应对 C5）**：CI 按变更文件顺序执行，目录是字母序（`ALB` 会排在 `KMS` 之前），一个 PR 同时含多层会失败。因此按层分 PR 合并：L1 → L2 → L3 → L4 → L5，每层合并并确认堆栈 `CREATE_COMPLETE` 后再合并下一层。

## 8. 仓库结构（目标）

仓库根目录与分层目录只放用 CloudFormation 堆栈部署的资源代码，布局与 `Foundation/dev2` 一致；不再使用的内容统一放在 `archive/`。**拷贝到 Foundation/dev2 时只拷贝 `templates/`（及需要时 `config.yml`）**。

```
mcp-hub-on-ecs/
├── config.yml                                  # 沿用参考格式：role / region / s3Bucket（dev2，待拷贝时确认）
├── templates/                                  # 全部堆栈，templates/<类型>/<应用>/<堆栈名>.yaml
│   ├── KMS/AWSMCP/
│   ├── Secrets_Manager/AWSMCP/
│   ├── Security_Group/AWSMCP/
│   ├── IAM/AWSMCP/
│   ├── IAM/AWSMCP-TargetAccount/               # 部署到“目标账号”，不在 dev2 部署
│   ├── ECR/AWSMCP/
│   ├── CloudWatch_Logs/AWSMCP/
│   ├── ALB/AWSMCP/
│   └── ECS/AWSMCP/
├── standards/                                  # tags.yaml（标签唯一来源）、naming.md
├── scripts/validate_standards.py               # 本地校验（见下）
├── .github/workflows/build-image.yml           # 镜像构建推送（见 §13）
├── docs/                                       # 设计文档（本文）
├── README.md
└── archive/                                    # 历史内容，不参与部署
    ├── terraform/  cfn/  shared/               # 旧 Terraform、旧目标账号角色、Lilly 通用模板参考
    ├── scripts/                                # 旧本地构建脚本（已被 workflow 取代）
    └── README-terraform.md  架构图/设计稿（drawio、HTML、png）
```

`validate_standards.py` 检查（可接入 PR 校验）：文件名 = 堆栈名 = 主资源名参数 Default；13 个标签参数的 Default 与 `standards/tags.yaml` 一致；无空 Default；路径无空格；每个 Output 带 Export 且导出名符合 `<堆栈名>:<输出名>`；Role 带 Boundary；ImportValue 的上游堆栈名参数存在对应文件。

## 9. 目标账号角色

- 位于 `templates/IAM/AWSMCP-TargetAccount/`，在**目标账号**的对应 CI/分支部署，不走 dev2
- 信任 dev2 的 task role：参数 `pSourceAccountId`（dev2 账号 ID）+ `pTaskRoleName`（Default = task role 文件名）→ 拼出 ARN；可选 `pExternalId`（`NA` = 不启用）
- task role 侧的 `sts:AssumeRole` 允许范围由 `-ecs-task-d-iamp-01` 的参数 `pTargetRoleArns` 决定：用 **账号 ID + 固定角色名拼 ARN**，不需要目标角色已存在，所以**不会再出现 Terraform 方案里“先 apply、再建角色、再 apply”的循环依赖**
- 权限：`ReadOnlyAccess` + 显式 Deny 数据读取（沿用上一轮实现），Role 同样带 Boundary

## 10. Terraform → CFN 映射

| Terraform | CFN 堆栈 |
|-----------|----------|
| `modules/vpc`（VPC/子网/IGW/NAT） | **不迁移**（复用已有，参数引用 VPC/子网 ID） |
| `modules/vpc` ALB/ECS SG | `-alb-d-sg-01`、`-ecs-d-sg-01`（+ `-cf-d-pl-01`） |
| `modules/iam` | `iamp` ×2 + `iamr` ×2（另新增 github-action 的 `iamp` + `iamr`） |
| `modules/alb`（ALB、监听器、TG、规则、改写、令牌） | `-d-alb-01`、`-d-tg-01/02`、`-d-sm-01` |
| `modules/ecs` | `-d-ecs-01`、`-d-ecssvc-01/02`、`-d-cwlg-01/02` |
| 构建脚本创建的 ECR | `-d-ecr-01/02`（新增 KMS、不可变 tag） |
| `archive/cfn/mcp-cross-account-role.yaml` | `templates/IAM/AWSMCP-TargetAccount/` 下两个堆栈 |
| 新增 | `-d-kms-01`（日志/ECR/密钥共用 CMK，满足 C8） |

## 11. 需确认的假设与风险

**开发前必须拿到的输入值（否则 Default 只能写占位，CI 无法真正部署）**

1. ~~dev2 账号/VPC/子网~~ → 已通过 profile `820607692027_awscn_cloudops_sso` 查得，见 §14
2. Cloudflare：回源网段清单（`-cf-d-pl-01` 暂用 Cloudflare 公布的 15 段 IPv4，需 Cloudflare 团队确认）、回源协议（HTTP 或 HTTPS）；若 HTTPS 回源，需要 ALB 上的证书 ARN（否则 443 监听器不创建，`NA`；dev2 已有 `*.dev.lilly.cn`、`*.dev.lilly.com.cn` 通配证书可选）
3. 试点目标账号 ID，及它走哪个 CI/分支部署
4. 本项目 GitHub 仓库：组织为 `EliLillyCo`，仓库名待新建（占位 `EliLillyCo/<待定>`；GitHub OIDC 角色信任 `repo:EliLillyCo/<repo>:*`）
5. SNOW CHG 号（暂用 `NA`）

**技术风险（开发期验证，不阻塞定稿）**

- 令牌校验：ALB 规则里的令牌用 Secrets Manager 动态引用 `{{resolve:secretsmanager:...}}` 注入，避免令牌进 git；需验证该属性支持动态引用，不行则退回“应用层 JWT 校验”（与 Entra 方案一致）
- ALB 规则路径改写（`Transforms`）CFN 已支持，但需在 cn-northwest-1 验证可用；不可用则改为让服务端识别带前缀路径
- Managed Prefix List 创建权限 CI 角色已具备；中国区实际可用性需在部署 L1 时确认，不可用则 `-alb-d-sg-01` 直接内联 CIDR 规则
- `IAM-China-Boundary` 已查：除一组 Deny（限制网络/IAM 用户/S3 桶创建/跨区域等）外 `Allow *`，**不阻止** task role 的 `sts:AssumeRole`、日志、ECS 运行动作；注意 `GuardCFNStacks` 保护 `China*` 命名的堆栈（本项目不使用）
- 中央 CI 角色权限已查：具备 `kms:* secretsmanager:* ecr:* ecs:* logs:* elasticloadbalancing:* cloudformation:*`、`ec2:CreateManagedPrefixList`、IAM 创建角色/策略，足够部署本项目
- ECS 服务关联角色 `AWSServiceRoleForECS` 已存在
- ALB 面向公网是否通过 Lilly 安全评审（drawio 里的 Cyber/Legal 评审流程）

## 12. 不在本设计内

CMP MCP、Copilot Studio / Power Automate 侧、CAFé 网关接入、窄工具开发（均沿用上一轮计划）；ALB 访问日志的 S3 桶（需要时按 `lly-nw-cloudops-awsmcp-d-s3-pri-01` 追加）；q/p 环境（后续按分支复制，`-d-` 换成 `-q-`/`-p-`）。

## 13. CFN 之外还需要什么（含应用代码如何发布）

### 13.1 应用代码：构建成镜像 → 推 ECR → 通过 CFN 发布

是的，应用以**容器镜像**形式交付。本项目没有自己的业务代码，应用代码是两个 fork 分支（`mengchencloud/mcp@feat/cross-account-support`、`@feature/aws-doc-streamable-http`），镜像在 GitHub Actions 里构建，沿用参考项目（`githubaction-ecs-workflow-demo`）的模式：

```
fork 分支代码
   │  GitHub Actions（workflow_dispatch，选 service / ref）
   ▼
OIDC 角色 `-github-action-d-iamr-01` → docker build（linux/amd64）→ 推送 ECR `-d-ecr-01/02`，tag = sha-<commit>
   │
   ▼  改 `-d-ecssvc-01/02` 的 pImageTag Default → 提 PR → 中央 CI 更新堆栈 → ECS 滚动发布
```

- **以 CFN 为唯一事实来源**：发布 = 改 `pImageTag` 并走 PR，不直接 `aws ecs update-service`，避免堆栈漂移
- 构建 workflow 只负责“构建 + 推送 + 打印新 tag”；ECR 仓库名、tag 规则由 `-d-ecr-01/02` 堆栈约束（tag 不可变）
- 本地 `scripts/build-and-deploy-aws-*.sh` 保留为应急手段（需有 dev2 凭证），不再改写 `terraform.tfvars`
- fork 本身的代码改动（allowlist、JWT audience、审计日志等）仍在 fork 仓库开发，改完后按上面流程出新镜像

### 13.2 其他不由本项目 CFN 部署、但必须就绪的东西

| 类别 | 内容 | 谁负责 |
|------|------|--------|
| 网络前置 | VPC、公有/私有子网、NAT 或 VPC Endpoint、路由 | Landing Zone / 网络团队（本项目只引用 ID） |
| IAM 前置 | `IAM-China-Boundary`、GitHub OIDC Provider、中央 CI 部署角色及其权限 | CloudOps |
| 服务关联角色 | `AWSServiceRoleForECS`（若不存在） | CloudOps（参考 `China_CICD/AWSServiceRoleForECS.yaml`） |
| 域名与证书 | Cloudflare 解析记录、证书、回源策略 | Cloudflare 团队（拿到 ALB DNS 后添加） |
| 目标账号 | 目标账号里的只读角色堆栈（§9） | 目标账号的 CI / 账号 owner |
| 令牌分发 | `-d-sm-01` 生成的 ALB 令牌，需把读取权限授予 Copilot Studio 连接配置的维护者 | CloudOps |
| 身份 | Entra 应用注册、JWT issuer/JWKS/audience（正式方案） | Entra 管理员 |
| 合规流程 | Cyber / Legal / 数据分级评审、ServiceNow 变更（CHG 号回填标签） | MCP Owner |
| 运行验证 | Copilot Studio → ALB 连通性、后台无人值守认证测试 | 联调阶段 |
| 监控告警 | CloudWatch 告警（5xx、UnHealthyHost、任务重启）——可作为后续追加的 `-d-cwal-01` 类堆栈 | CloudOps（后续） |


## 14. dev2 环境已核对的事实（只读查询，账号 820607692027，cn-northwest-1）

| 项 | 值 |
|----|----|
| VPC | `vpc-0c748129d3dc6da22`（ChinaDevelopment-2VPC，`10.136.160.0/21`），无 NAT、无 ECR/STS/Logs VPC Endpoint（仅 S3 网关、Firehose） |
| 私有子网（ECS，`10.136.160.0/21` 内） | A `subnet-0a41314598dfbbadd`、B `subnet-05144622b7f3b1825`、C `subnet-03c2ba1165a2999ad`；默认路由经 **Transit Gateway**（集中出口） |
| 公有子网（仅 ALB） | A `subnet-05143f4d153a76934`、B `subnet-06beee1929a288768`、C `subnet-029ca324a583fb6df`；默认路由经 **GWLB 端点**（流量检查），GWLB 子网再到 IGW |
| 已有前置 | `IAM-China-Boundary`(v3)、`AWSServiceRoleForECS`、GitHub OIDC Provider、CI 角色 `lly-nw-cloudops-github-d-iamr-01`、ACM 通配证书 `*.dev.lilly.cn` / `*.dev.lilly.com.cn` |
| 既有命名惯例（与本设计一致） | ECS 集群 `lly-nw-com-stp-d-ecs-01`、ECR `lly-nw-com-dify-eks-d-ecr-01`、ALB `lly-nw-com-Aff-iMoney-d-alb` |
| 日志组惯例 | `/aws/ecs/<名称>`，30 天保留，KMS 加密 → **`cwlg` 堆栈的日志组名 = `/aws/ecs/` + 文件名** |
| 已有 KMS 日志密钥策略 | 与本设计 `-d-kms-01` 的写法一致（root + 管理员角色 + `logs.cn-northwest-1.amazonaws.com.cn` 服务主体） |

对设计的影响：

- 私有子网没有本地 NAT/VPCE，出网（ECR、STS、`docs.amazonaws.cn`）依赖 TGW 集中出口，**需在 L3/L5 联调时验证可达**；如不可达，追加 VPCE 堆栈（`sts`、`ecr.api`、`ecr.dkr`、`logs`，S3 网关已有）
- 公有 ALB 的入站流量会经过 GWLB 检查，需确认防火墙策略放行 Cloudflare 网段到 ALB
- 子网 ID 作为各模板 Default（`List<AWS::EC2::Subnet::Id>`）

## 15. 开发与 dry run 结果（dev2 真实环境，测试栈已清理）

方法：把全部 23 个模板复制到 `/tmp`，前缀换成 `lly-nw-cloudops-awsmcpt`、去掉 Retain，按 L1→L5 + 目标账号角色真实部署，验证后反向删除；原模板与现有资源未改动。

**静态校验**：`validate_standards.py`、cfn-lint（用中央 `security/.cfnlintrc`）、cfn-guard 3.1.1（中央 `aws_iam_role` / `aws_kms` / `aws_security_group` 规则）全部通过；IAM Access Analyzer 对两个策略无告警。

**真实部署验证通过的行为**
- L1–L5 及目标账号角色共 23 个栈全部 `CREATE_COMPLETE`；中国区 Managed Prefix List、Secrets Manager 生成令牌、ECR（KMS + 不可变 tag）、KMS 加密日志组均可用
- Fargate 任务在私有子网通过 TGW/GWLB 出网拉到公网镜像（`public.ecr.aws`），日志写入 KMS 加密的日志组，目标组 healthy
- ALB：无令牌 401、错误令牌 401、`Bearer <token>` 与裸令牌均 200、未知路径 404、无目标时 503；**路径改写生效**（`/aws-api/etc/hostname` → 容器 `/etc/hostname`）；令牌来自 Secrets Manager 动态引用（令牌不进 git）
- 条件分支：`pCertificateArn` 配置后 HTTPS 监听器与规则同样生效（`*.dev.lilly.cn` 通配证书）；`pRequireAuth=false` 时去掉令牌条件与 401 规则
- IAM 模拟：task 角色只能 assume 目标只读角色（其他角色被 `IAM-China-Boundary` 拦截），数据读取显式拒绝；目标角色能读资源配置/日志，读不了 secrets/对象内容，不能写

**发现并已处理**
- 中央 PR 校验的 cfn-lint 不识别 ALB 规则的 `Transforms`（E3002），已在 tg 模板的转发规则上用资源级 `Metadata.cfn-lint.config.ignore_checks` 忽略
- 校验脚本抓到并促成修正：`TaskDefinitionArn` 输出缺少 Export

**未能验证 / 需要你知道**
- **fork 镜像未能在本机构建**（容器内访问不了 PyPI），所以 fork 代码本身（allowlist、跨账号 `call_aws`、streamable-http）没有在 ECS 上实测；基础设施层用公共 Python 镜像代替，路由/鉴权/改写/日志均已验证。fork 镜像请用 GitHub Actions 构建后再联调
- 本机推送大镜像到中国区 ECR 很慢（569 MB 约 45 分钟仍未完成），不建议在本机推送
- **`ec2:DeleteManagedPrefixList` 与 `kms:ScheduleKeyDeletion` 在本账号对我的 SSO 角色不可用**；中央 CI 角色同样没有 `DeleteManagedPrefixList`（只有 Create/Modify/Restore）。含义：① 生产模板对 KMS、ECR、日志组、密钥已设 `Retain`；② **`-cf-d-pl-01` 不能被 CI 删除或“替换式更新”**（改名会失败），改 Cloudflare 网段只做原地修改 Entries；如需删除，找有权限的管理员
- 因上述权限限制，测试时创建的 2 个资源无法删除，见本次交付说明

