# IAM Module Outputs

output "task_execution_role_arn" {
  description = "ARN of ECS task execution role"
  value       = aws_iam_role.task_execution.arn
}

output "task_execution_role_name" {
  description = "Name of ECS task execution role"
  value       = aws_iam_role.task_execution.name
}

output "task_role_arn" {
  description = "ARN of ECS task role"
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Name of ECS task role"
  value       = aws_iam_role.task.name
}

