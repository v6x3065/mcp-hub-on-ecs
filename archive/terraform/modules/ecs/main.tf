# ECS Module - ECS cluster and services for multiple MCP servers

# ECS Cluster (shared by all MCP services)
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}"

  # Container Insights disabled for cost savings
  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = merge(var.tags, {
    Name       = "${var.project_name}-${var.environment}-cluster"
    DenyDelete = "true"
  })
}

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 1
    capacity_provider = "FARGATE"
  }
}

# CloudWatch Log Groups (one per MCP service)
resource "aws_cloudwatch_log_group" "mcp_services" {
  for_each = var.mcp_services

  name              = "/ecs/${var.project_name}-${var.environment}-${each.key}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name       = "${var.project_name}-${var.environment}-${each.key}-logs"
    Service    = each.key
    DenyDelete = "true"
  })
}

# ECS Task Definitions (one per MCP service)
resource "aws_ecs_task_definition" "mcp_services" {
  for_each = var.mcp_services

  family                   = "${var.project_name}-${var.environment}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  # x86_64 architecture for compatibility
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name  = each.key
      image = each.value.image

      # Port mapping
      portMappings = [
        {
          containerPort = each.value.container_port
          hostPort      = each.value.container_port
          protocol      = "tcp"
        }
      ]

      # Environment variables from configuration
      environment = [
        for key, value in each.value.environment_vars : {
          name  = key
          value = value
        }
      ]

      # CloudWatch Logs configuration
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.mcp_services[each.key].name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      # Essential container
      essential = true
    }
  ])

  tags = merge(var.tags, {
    Name       = "${var.project_name}-${var.environment}-${each.key}-task"
    Service    = each.key
    DenyDelete = "true"
  })
}

# ECS Services (one per MCP service)
resource "aws_ecs_service" "mcp_services" {
  for_each = var.mcp_services

  name             = "${var.project_name}-${var.environment}-${each.key}"
  cluster          = aws_ecs_cluster.main.id
  task_definition  = aws_ecs_task_definition.mcp_services[each.key].arn
  desired_count    = each.value.desired_count
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  # Network configuration for Fargate
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  # Load balancer integration
  load_balancer {
    target_group_arn = each.value.target_group_arn
    container_name   = each.key
    container_port   = each.value.container_port
  }

  # Health check grace period
  health_check_grace_period_seconds = 60

  tags = merge(var.tags, {
    Name       = "${var.project_name}-${var.environment}-${each.key}-service"
    Service    = each.key
    DenyDelete = "true"
  })
}
