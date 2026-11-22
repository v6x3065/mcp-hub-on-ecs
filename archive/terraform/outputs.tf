# ALB Outputs
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.alb.alb_arn
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer (for Route53)"
  value       = module.alb.alb_zone_id
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener"
  value       = module.alb.http_listener_arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (null if not managed by Terraform)"
  value       = module.alb.https_listener_arn
}

output "target_group_arns" {
  description = "Map of target group ARNs by service name"
  value       = module.alb.target_group_arns
}

output "mcp_endpoints" {
  description = "MCP endpoint URLs for each service"
  value       = module.alb.mcp_endpoints
}

# ECS Outputs
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs.cluster_arn
}

output "ecs_service_names" {
  description = "Map of ECS service names by MCP service"
  value       = module.ecs.service_names
}

output "ecs_service_arns" {
  description = "Map of ECS service ARNs by MCP service"
  value       = module.ecs.service_arns
}

output "log_group_names" {
  description = "Map of CloudWatch log group names by MCP service"
  value       = module.ecs.log_group_names
}

# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployment configuration"
  value = {
    https_enabled           = var.enable_https
    certificate_configured  = var.certificate_arn != ""
    http_redirect           = var.http_to_https_redirect
    manual_https_management = var.manage_https_manually
    available_services      = keys(module.alb.target_group_arns)
  }
}

# IAM Outputs
output "task_role_arn" {
  description = "ARN of the ECS task role (used for cross-account assume role)"
  value       = module.iam.task_role_arn
}
