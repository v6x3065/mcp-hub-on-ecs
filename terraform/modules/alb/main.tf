# ALB Module - Application Load Balancer for ECS MCP hosting

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection       = false
  enable_http2                     = true
  enable_cross_zone_load_balancing = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-alb"
    }
  )
}

# Target Groups for MCP services
resource "aws_lb_target_group" "mcp_services" {
  for_each = var.target_groups

  name        = "${var.project_name}-${var.environment}-${each.value.name_suffix}"
  port        = each.value.port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 10
    interval            = 30
    path                = each.value.health_check_path
    protocol            = "HTTP"
    matcher             = each.value.health_check_matcher
  }

  deregistration_delay = 60

  tags = merge(
    var.tags,
    {
      Name    = "${var.project_name}-${var.environment}-${each.value.name_suffix}"
      Service = each.key
    }
  )
}

# HTTP Listener (port 80) - Always created
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # Default action: Redirect to HTTPS or return 404
  default_action {
    type = var.http_to_https_redirect && var.enable_https ? "redirect" : "fixed-response"

    # Redirect configuration (when http_to_https_redirect=true)
    dynamic "redirect" {
      for_each = var.http_to_https_redirect && var.enable_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    # Fixed response configuration (when http_to_https_redirect=false)
    dynamic "fixed_response" {
      for_each = var.http_to_https_redirect && var.enable_https ? [] : [1]
      content {
        content_type = "application/json"
        message_body = jsonencode({
          error           = "Not Found"
          message         = "Please use a valid MCP endpoint path"
          available_paths = [for k, v in var.listener_rules : v.path_pattern]
          example         = "http://${aws_lb.main.dns_name}/aws-api/mcp"
        })
        status_code = "404"
      }
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-http-listener"
    }
  )
}

# HTTPS Listener (port 443) - Conditionally created
resource "aws_lb_listener" "https" {
  count = var.enable_https && !var.manage_https_manually ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  # Default action: Return 404
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "application/json"
      message_body = jsonencode({
        error           = "Not Found"
        message         = "Please use a valid MCP endpoint path"
        available_paths = [for k, v in var.listener_rules : v.path_pattern]
        example         = "https://${aws_lb.main.dns_name}/aws-api/mcp"
      })
      status_code = "404"
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-https-listener"
    }
  )
}

# HTTP Listener Rules - Path-based routing
resource "aws_lb_listener_rule" "http_rules" {
  for_each = var.http_to_https_redirect && var.enable_https ? {} : var.listener_rules

  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mcp_services[each.value.target_group_key].arn
  }

  # URL rewrite transform to strip the service prefix
  # Example: /aws-api/mcp -> /mcp
  dynamic "transform" {
    for_each = [1]
    content {
      type = "url-rewrite"
      
      dynamic "url_rewrite_config" {
        for_each = [1]
        content {
          dynamic "rewrite" {
            for_each = [1]
            content {
              regex   = "^/${each.key}/(.*)$"
              replace = "/$1"
            }
          }
        }
      }
    }
  }

  condition {
    path_pattern {
      values = [each.value.path_pattern]
    }
  }

  tags = merge(
    var.tags,
    {
      Name    = "${var.project_name}-${var.environment}-http-${each.key}"
      Service = each.key
    }
  )
}

# HTTPS Listener Rules - Path-based routing
resource "aws_lb_listener_rule" "https_rules" {
  for_each = var.enable_https && !var.manage_https_manually ? var.listener_rules : {}

  listener_arn = aws_lb_listener.https[0].arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mcp_services[each.value.target_group_key].arn
  }

  # URL rewrite transform to strip the service prefix
  # Example: /aws-api/mcp -> /mcp
  dynamic "transform" {
    for_each = [1]
    content {
      type = "url-rewrite"
      
      dynamic "url_rewrite_config" {
        for_each = [1]
        content {
          dynamic "rewrite" {
            for_each = [1]
            content {
              regex   = "^/${each.key}/(.*)$"
              replace = "/$1"
            }
          }
        }
      }
    }
  }

  condition {
    path_pattern {
      values = [each.value.path_pattern]
    }
  }

  tags = merge(
    var.tags,
    {
      Name    = "${var.project_name}-${var.environment}-https-${each.key}"
      Service = each.key
    }
  )
}
