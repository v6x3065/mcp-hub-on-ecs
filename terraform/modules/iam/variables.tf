# IAM Module Variables
# Will be populated in task 3

variable "project_name" {
  type        = string
  description = "Project name for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "account_id" {
  type        = string
  description = "AWS account ID"
}

variable "tags" {
  type        = map(string)
  description = "Common tags for all resources"
  default     = {}
}

variable "assume_role_target_arns" {
  type        = list(string)
  description = "Target role ARNs the task role may assume (cross-account read-only roles)"
  default     = []
}

variable "attach_same_account_readonly" {
  type        = bool
  description = "Attach the AWS managed ReadOnlyAccess policy to the task role for same-account queries"
  default     = false
}
