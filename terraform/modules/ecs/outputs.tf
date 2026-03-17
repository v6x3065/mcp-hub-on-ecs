# ECS Module Outputs

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "service_names" {
  description = "Map of ECS service names by MCP service"
  value       = { for k, svc in aws_ecs_service.mcp_services : k => svc.name }
}

output "service_arns" {
  description = "Map of ECS service ARNs by MCP service"
  value       = { for k, svc in aws_ecs_service.mcp_services : k => svc.id }
}

output "task_definition_arns" {
  description = "Map of task definition ARNs by MCP service"
  value       = { for k, td in aws_ecs_task_definition.mcp_services : k => td.arn }
}

output "log_group_names" {
  description = "Map of CloudWatch log group names by MCP service"
  value       = { for k, lg in aws_cloudwatch_log_group.mcp_services : k => lg.name }
}

output "log_group_arns" {
  description = "Map of CloudWatch log group ARNs by MCP service"
  value       = { for k, lg in aws_cloudwatch_log_group.mcp_services : k => lg.arn }
}
