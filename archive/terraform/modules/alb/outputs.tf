# ALB Module Outputs

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer (for Route53)"
  value       = aws_lb.main.zone_id
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (null if not managed by Terraform)"
  value       = var.enable_https && !var.manage_https_manually ? aws_lb_listener.https[0].arn : null
}

output "target_group_arns" {
  description = "Map of target group ARNs by service name"
  value       = { for k, tg in aws_lb_target_group.mcp_services : k => tg.arn }
}

output "target_group_names" {
  description = "Map of target group names by service name"
  value       = { for k, tg in aws_lb_target_group.mcp_services : k => tg.name }
}

output "mcp_endpoints" {
  description = "MCP endpoint URLs for each service"
  value = {
    http = var.http_to_https_redirect && var.enable_https ? null : {
      for k, v in var.listener_rules :
      k => "http://${aws_lb.main.dns_name}${replace(v.path_pattern, "/*", "/mcp")}"
    }
    https = var.enable_https ? {
      for k, v in var.listener_rules :
      k => "https://${aws_lb.main.dns_name}${replace(v.path_pattern, "/*", "/mcp")}"
    } : null
  }
}
