# VPC Module Variables
# Will be populated in task 2

variable "project_name" {
  type        = string
  description = "Project name for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
}

variable "alb_ingress_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the ALB on ports 80/443. Empty list = no inbound rules."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Common tags for all resources"
  default     = {}
}
