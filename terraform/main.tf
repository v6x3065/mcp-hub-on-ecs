# Main Terraform configuration for ECS Remote MCP Hosting Platform
# This file orchestrates all modules to deploy the complete infrastructure

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get current IP for security group rules
data "http" "myip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  my_ip      = "${chomp(data.http.myip.response_body)}/32"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  # Use custom mcp_services if provided, otherwise use default configurations
  mcp_services_config = var.mcp_services != null ? var.mcp_services : local.mcp_services
}

# VPC Module - Creates networking infrastructure
module "vpc" {
  source = "./modules/vpc"

  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr

  tags = local.common_tags
}

# IAM Module - Creates ECS task roles and execution roles
module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
  environment  = var.environment
  account_id   = local.account_id

  tags = local.common_tags
}

# ALB Module - Creates Application Load Balancer and target group
module "alb" {
  source = "./modules/alb"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.vpc.alb_security_group_id

  # Certificate and HTTPS configuration
  enable_https           = var.enable_https
  certificate_arn        = var.certificate_arn
  manage_https_manually  = var.manage_https_manually
  http_to_https_redirect = var.http_to_https_redirect
  ssl_policy             = var.ssl_policy

  # Authentication
  auth_token  = var.auth_token
  enable_auth = nonsensitive(var.auth_token != "")

  # Target groups for MCP services - dynamically created from mcp_services
  target_groups = {
    for name, config in local.mcp_services_config : name => {
      name_suffix          = "${name}-tg"
      port                 = config.container_port
      health_check_path    = try(config.health_check_path, "/")
      health_check_matcher = "200,404"
    } if config.enabled
  }

  # Listener rules for path-based routing - dynamically created from mcp_services
  listener_rules = {
    for name, config in local.mcp_services_config : name => {
      path_pattern     = config.path_pattern
      priority         = config.priority
      target_group_key = name
      require_auth     = try(config.require_auth, true)
      skip_rewrite     = try(config.skip_rewrite, false)
    } if config.enabled
  }

  tags = local.common_tags
}

# ECS Module - Creates ECS cluster and services for each enabled MCP server
module "ecs" {
  source = "./modules/ecs"

  project_name          = var.project_name
  environment           = var.environment
  region                = var.region
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  ecs_security_group_id = module.vpc.ecs_security_group_id

  task_execution_role_arn = module.iam.task_execution_role_arn
  task_role_arn           = module.iam.task_role_arn

  # Pass enabled MCP services configuration
  mcp_services = {
    for name, config in local.mcp_services_config : name => {
      image            = config.image
      cpu              = config.cpu
      memory           = config.memory
      desired_count    = config.desired_count
      container_port   = config.container_port
      target_group_arn = module.alb.target_group_arns[name]
      environment_vars = config.environment_vars
    } if config.enabled
  }

  log_retention_days = var.log_retention_days

  tags = local.common_tags
}
