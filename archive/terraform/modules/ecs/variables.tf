# ECS Module Variables

variable "project_name" {
  type        = string
  description = "Project name for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "region" {
  type        = string
  description = "AWS region"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for ECS tasks"
}

variable "ecs_security_group_id" {
  type        = string
  description = "ECS security group ID"
}

variable "task_execution_role_arn" {
  type        = string
  description = "ECS task execution role ARN"
}

variable "task_role_arn" {
  type        = string
  description = "ECS task role ARN"
}

variable "mcp_services" {
  description = "Map of MCP services to deploy"
  type = map(object({
    image            = string
    cpu              = number
    memory           = number
    desired_count    = number
    container_port   = number
    target_group_arn = string
    environment_vars = map(string)
  }))
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch Logs retention period in days"
}

variable "tags" {
  type        = map(string)
  description = "Common tags for all resources"
  default     = {}
}
