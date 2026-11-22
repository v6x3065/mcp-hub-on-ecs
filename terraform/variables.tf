variable "project_name" {
  type        = string
  description = "Project name for resource naming"
  default     = "aiops-mcp-ecs"
}

variable "region" {
  type        = string
  description = "AWS region for deployment"
  default     = "cn-northwest-1"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
  default     = "dev"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch Logs retention period in days"
  default     = 7
}

# ============================================================================
# Access Control
# ============================================================================

variable "alb_ingress_cidrs" {
  type        = list(string)
  description = <<-EOT
    CIDR blocks allowed to reach the ALB on ports 80/443 (e.g. Cloudflare origin ranges
    and your test client IPs). Empty list = no inbound rules, so the ALB is unreachable.
  EOT
  default     = []
}

variable "assume_role_target_arns" {
  type        = list(string)
  description = <<-EOT
    Approved target role ARNs the ECS task role may assume (cross-account read-only roles,
    e.g. "arn:aws-cn:iam::<account-id>:role/McpCrossAccountReadOnly").
    Empty list = the task role cannot assume any role.
  EOT
  default     = []
}

variable "attach_same_account_readonly" {
  type        = bool
  description = "Attach AWS managed ReadOnlyAccess to the task role so MCP can query the deployment account itself."
  default     = false
}

variable "aws_api_account_allowlist" {
  type        = string
  description = <<-EOT
    JSON map of account alias to target role, passed to aws-api as AWS_API_MCP_ACCOUNT_ALLOWLIST, e.g.
    {"prod-core":{"role_arn":"arn:aws-cn:iam::111122223333:role/McpCrossAccountReadOnly"}}
    Only enforced by a fork build that implements the allowlist; stock images ignore it.
  EOT
  default     = ""
}

variable "mcp_allowed_hosts" {
  type        = string
  description = "Allowed Host header / Origin value(s) for the aws-api server (e.g. the Cloudflare-fronted domain). \"*\" disables the check."
  default     = "*"
}

# ============================================================================
# MCP Server Authentication (server-side)
# ============================================================================

variable "mcp_auth_type" {
  type        = string
  description = "aws-api server auth: \"no-auth\" (rely on the ALB token) or \"oauth\" (validate JWTs, e.g. Entra ID)"
  default     = "no-auth"

  validation {
    condition     = contains(["no-auth", "oauth"], var.mcp_auth_type)
    error_message = "mcp_auth_type must be \"no-auth\" or \"oauth\"."
  }
}

variable "mcp_auth_issuer" {
  type        = string
  description = "JWT issuer (AUTH_ISSUER); required when mcp_auth_type = \"oauth\""
  default     = ""
}

variable "mcp_auth_jwks_uri" {
  type        = string
  description = "JWKS URI (AUTH_JWKS_URI); required when mcp_auth_type = \"oauth\""
  default     = ""
}

# ============================================================================
# Authentication
# ============================================================================

variable "auth_token" {
  type        = string
  description = <<-EOT
    Bearer token for MCP endpoint authentication.
    When set, ALB requires "Authorization: Bearer <token>" header on all requests.
    When empty, no authentication is enforced (not recommended for production).
    
    Generate a token: openssl rand -base64 32
    
    Client configuration example:
      {
        "url": "https://your-domain.com/aws-api/mcp",
        "headers": { "Authorization": "Bearer your-token-here" }
      }
  EOT
  default     = ""
  sensitive   = true
}

# ============================================================================
# MCP Services Enable/Disable Controls
# ============================================================================
# Simple boolean flags to control which MCP services to deploy

variable "deploy_aws_api" {
  type        = bool
  description = "Deploy AWS API MCP Server (provides AWS CLI command execution)"
  default     = true
}

variable "deploy_aws_doc" {
  type        = bool
  description = "Deploy AWS Documentation MCP Server (provides AWS documentation search and reading)"
  default     = false  # Disabled to stop excessive NAT Gateway costs from failed task restarts
}

variable "deploy_aws_knowledge" {
  type        = bool
  description = "Deploy AWS Knowledge MCP Server (provides AWS documentation with advanced search)"
  default     = false
}

# Image overrides - change these when upstream PRs are merged
variable "aws_api_image" {
  type        = string
  description = "aws-api-mcp-server image. Use custom fork until PR #2702 is merged."
  default     = "" # empty = use ECR default: <account_id>.dkr.ecr.<region>.amazonaws.com.cn/aws-api-mcp-server:cross-account
}

variable "aws_doc_image" {
  type        = string
  description = "aws-documentation-mcp-server image. Use custom fork until PR #2247 is merged."
  default     = "" # empty = use ECR default: <account_id>.dkr.ecr.<region>.amazonaws.com.cn/aws-documentation-mcp-server-http:latest
}

# ============================================================================
# MCP Services Configuration
# ============================================================================
# Internal configuration for MCP services - automatically filtered by deploy_* variables

locals {
  # Define all available MCP services with their configurations
  all_mcp_services = {
    aws-api = {
      enabled        = var.deploy_aws_api
      image          = var.aws_api_image != "" ? var.aws_api_image : "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com.cn/aws-api-mcp-server:cross-account"
      cpu            = 512
      memory         = 1024
      desired_count  = 1
      container_port = 8000
      path_pattern   = "/aws-api/*"
      priority       = 100
      health_check_path = "/"
      require_auth   = true
      skip_rewrite   = false
      environment_vars = merge(
        {
          AWS_REGION                       = var.region
          AWS_API_MCP_TRANSPORT            = "streamable-http"
          AWS_API_MCP_STATELESS_HTTP       = "true"
          AWS_API_MCP_HOST                 = "0.0.0.0"
          AWS_API_MCP_PORT                 = "8000"
          AWS_API_MCP_ALLOWED_HOSTS        = var.mcp_allowed_hosts
          AWS_API_MCP_ALLOWED_ORIGINS      = var.mcp_allowed_hosts
          AWS_API_MCP_ENABLE_CROSS_ACCOUNT = "true"
          AWS_API_MCP_TELEMETRY            = "false"
          READ_OPERATIONS_ONLY             = "true"
          AUTH_TYPE                        = var.mcp_auth_type
        },
        var.mcp_auth_type == "oauth" ? {
          AUTH_ISSUER   = var.mcp_auth_issuer
          AUTH_JWKS_URI = var.mcp_auth_jwks_uri
        } : {},
        var.aws_api_account_allowlist != "" ? {
          AWS_API_MCP_ACCOUNT_ALLOWLIST = var.aws_api_account_allowlist
        } : {}
      )
    }
    
    aws-doc = {
      enabled        = var.deploy_aws_doc
      image          = var.aws_doc_image != "" ? var.aws_doc_image : "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com.cn/aws-documentation-mcp-server-http:latest"
      cpu            = 512
      memory         = 1024
      desired_count  = 1
      container_port = 8000
      path_pattern   = "/aws-doc/*"
      priority       = 200
      health_check_path = "/"
      require_auth   = true
      skip_rewrite   = false
      environment_vars = {
        AWS_DOCUMENTATION_PARTITION = "aws-cn"
        FASTMCP_TRANSPORT           = "streamable-http"
        FASTMCP_STATELESS_HTTP      = "true"
        FASTMCP_PORT                = "8000"
        FASTMCP_HOST                = "0.0.0.0"
        FASTMCP_LOG_LEVEL           = "INFO"
      }
    }
    
    aws-knowledge = {
      enabled        = var.deploy_aws_knowledge
      image          = "public.ecr.aws/awslabs-mcp/awslabs/aws-knowledge-mcp-server:latest"
      cpu            = 512
      memory         = 1024
      desired_count  = 1
      container_port = 8000
      path_pattern   = "/aws-knowledge/*"
      priority       = 300
      health_check_path = "/"
      require_auth   = true
      skip_rewrite   = false
      environment_vars = {
        FASTMCP_TRANSPORT = "http"
        FASTMCP_PORT      = "8000"
        FASTMCP_HOST      = "0.0.0.0"
        FASTMCP_LOG_LEVEL = "INFO"
      }
    }
  }
  
  # Filter to only enabled services
  mcp_services = {
    for name, config in local.all_mcp_services : name => config
    if config.enabled
  }
}

# Legacy variable for backward compatibility and advanced customization
variable "mcp_services" {
  description = <<-EOT
    Advanced: Override MCP services configuration.
    For most users, use deploy_aws_api, deploy_aws_doc, deploy_aws_knowledge variables instead.
    
    This variable allows full customization of MCP services including:
    - Custom container images
    - Custom resource allocation (CPU/Memory)
    - Custom environment variables
    - Custom path patterns and priorities
    
    When set, this overrides the default configurations and deploy_* variables.
  EOT

  type = map(object({
    enabled          = bool
    image            = string
    cpu              = number
    memory           = number
    desired_count    = number
    container_port   = number
    path_pattern     = string
    priority         = number
    health_check_path = optional(string, "/")
    require_auth      = optional(bool, true)
    skip_rewrite      = optional(bool, false)
    environment_vars = map(string)
  }))

  default = null
}

# ============================================================================
# Certificate and HTTPS Configuration
# ============================================================================
# These variables control how HTTPS is configured for the ALB.
# Choose the configuration that matches your deployment scenario.

variable "enable_https" {
  type        = bool
  description = <<-EOT
    Enable HTTPS listener on port 443.
    
    Usage Scenarios:
    - false: POC/Development - HTTP only (port 80), use local proxy for testing
    - true:  Production - Enable HTTPS with certificate
    
    When false:
    - Only HTTP listener (port 80) is created
    - Access via: http://alb-dns-name/aws-api/mcp
    - Use local socat proxy to convert to HTTPS if needed
    
    When true:
    - Both HTTP (80) and HTTPS (443) listeners are created
    - Requires certificate_arn (unless manage_https_manually=true)
    - Access via: https://your-domain.com/aws-api/mcp
  EOT
  default     = false
}

variable "certificate_arn" {
  type        = string
  description = <<-EOT
    ACM certificate ARN for HTTPS listener.
    Required when enable_https=true and manage_https_manually=false.
    
    Usage Scenarios:
    
    Scenario 1 - ACM Managed Certificate (Recommended):
      certificate_arn = "arn:aws-cn:acm:cn-northwest-1:123456789012:certificate/xxx"
      - Certificate managed in AWS Certificate Manager
      - Supports auto-renewal
      - Domain must be ICP filed (China regions)
    
    Scenario 2 - Imported Certificate:
      certificate_arn = "arn:aws-cn:acm:cn-northwest-1:123456789012:certificate/xxx"
      - Certificate imported to ACM (e.g., Let's Encrypt, commercial CA)
      - Manual renewal required
      - Domain must be ICP filed (China regions)
    
    Scenario 3 - Manual HTTPS Management:
      certificate_arn = ""
      manage_https_manually = true
      - HTTPS listener configured manually in AWS Console
      - Useful for cross-account certificate scenarios
      - Terraform will not manage HTTPS listener
    
    To get certificate ARN:
      aws acm list-certificates --region cn-northwest-1
    
    China Region Requirements:
    - Domain MUST have valid ICP filing (备案)
    - Certificate domain must match ICP filed domain
  EOT
  default     = ""
}

variable "manage_https_manually" {
  type        = bool
  description = <<-EOT
    Set to true if HTTPS listener will be configured manually outside Terraform.
    
    Usage Scenarios:
    
    Scenario 1 - Cross-Account Certificate:
      manage_https_manually = true
      - Certificate managed in different AWS account
      - Domain DNS managed by another team
      - Terraform creates ALB and HTTP listener only
      - Manually add HTTPS listener in AWS Console
    
    Scenario 2 - External Certificate Management:
      manage_https_manually = true
      - Certificate managed outside AWS (e.g., corporate PKI)
      - Complex certificate rotation requirements
      - Need manual control over HTTPS configuration
    
    When true:
    - Terraform will NOT create or manage HTTPS listener
    - Terraform will NOT create HTTPS listener rules
    - You must manually configure HTTPS listener and rules in AWS Console
    - HTTP listener and rules will still be created by Terraform
    
    When false (default):
    - Terraform manages HTTPS listener (if enable_https=true)
    - Terraform manages HTTPS listener rules
    - Recommended for most scenarios
  EOT
  default     = false
}

variable "http_to_https_redirect" {
  type        = bool
  description = <<-EOT
    Redirect HTTP (port 80) traffic to HTTPS (port 443).
    Only applies when enable_https=true.
    
    Usage Scenarios:
    
    Scenario 1 - Production (Redirect):
      http_to_https_redirect = true
      - Force all traffic to use HTTPS
      - HTTP requests automatically redirected to HTTPS
      - Recommended for production environments
      - Users accessing http://domain.com will be redirected to https://domain.com
    
    Scenario 2 - Mixed Mode (No Redirect):
      http_to_https_redirect = false
      - Allow both HTTP and HTTPS access
      - Useful for gradual migration
      - Useful for testing/POC alongside production
      - HTTP: http://alb-dns-name/aws-api/mcp (for testing)
      - HTTPS: https://your-domain.com/aws-api/mcp (for production)
    
    When true:
    - HTTP listener returns 301 redirect to HTTPS
    - All traffic forced to HTTPS
    
    When false:
    - HTTP listener serves traffic normally
    - Both HTTP and HTTPS endpoints available
  EOT
  default     = false
}

variable "ssl_policy" {
  type        = string
  description = <<-EOT
    SSL/TLS policy for HTTPS listener.
    
    Recommended policies:
    - ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09 (Default, most secure)
    - ELBSecurityPolicy-TLS13-1-2-2021-06 (TLS 1.3 and 1.2)
    - ELBSecurityPolicy-2016-08 (Backward compatibility)
    
    See: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-https-listener.html#describe-ssl-policies
  EOT
  default     = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
}

# ============================================================================
# Configuration Examples
# ============================================================================
# 
# Example 1: POC/Development (HTTP Only)
# ---------------------------------------
# enable_https           = false
# certificate_arn        = ""
# 
# Access: http://alb-dns-name.elb.amazonaws.com.cn/aws-api/mcp
# Or use local proxy: socat TCP-LISTEN:3000,fork TCP:alb-dns-name:80
#
# Example 2: Production (HTTPS with ACM)
# ---------------------------------------
# enable_https           = true
# certificate_arn        = "arn:aws-cn:acm:cn-northwest-1:123456789012:certificate/xxx"
# http_to_https_redirect = true
# 
# Access: https://your-domain.com/aws-api/mcp
# HTTP requests automatically redirected to HTTPS
#
# Example 3: Mixed Mode (HTTP + HTTPS)
# -------------------------------------
# enable_https           = true
# certificate_arn        = "arn:aws-cn:acm:cn-northwest-1:123456789012:certificate/xxx"
# http_to_https_redirect = false
# 
# Access HTTP: http://alb-dns-name.elb.amazonaws.com.cn/aws-api/mcp
# Access HTTPS: https://your-domain.com/aws-api/mcp
#
# Example 4: Cross-Account Certificate
# -------------------------------------
# enable_https           = true
# manage_https_manually  = true
# 
# Terraform creates HTTP listener only
# Manually configure HTTPS listener in AWS Console
# ============================================================================
