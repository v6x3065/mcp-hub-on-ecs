# ALB Module Variables

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Certificate and HTTPS Configuration
variable "enable_https" {
  description = "Enable HTTPS listener on port 443"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener"
  type        = string
  default     = ""
}

variable "manage_https_manually" {
  description = "Set to true if HTTPS listener will be configured manually outside Terraform"
  type        = bool
  default     = false
}

variable "http_to_https_redirect" {
  description = "Redirect HTTP (80) to HTTPS (443). Only applies when enable_https is true."
  type        = bool
  default     = false
}

variable "ssl_policy" {
  description = "SSL policy for HTTPS listener"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
}

# Target Groups Configuration
variable "target_groups" {
  description = "Map of target groups to create for different MCP services"
  type = map(object({
    name_suffix          = string
    port                 = number
    health_check_path    = string
    health_check_matcher = string
  }))
  default = {}
}

# Listener Rules Configuration
variable "listener_rules" {
  description = "Map of listener rules for path-based routing"
  type = map(object({
    path_pattern     = string
    priority         = number
    target_group_key = string
  }))
  default = {}
}

# Authentication
variable "auth_token" {
  description = "Bearer token for MCP endpoint auth. When set, ALB rejects requests without valid Authorization header."
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_auth" {
  description = "Enable bearer token authentication. Set to true when auth_token is provided."
  type        = bool
  default     = false
}
