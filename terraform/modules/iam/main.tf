# IAM Module - Task roles and execution roles for ECS

# ============================================================================
# ECS Task Execution Role
# ============================================================================
# This role is used by ECS to pull container images from ECR and write logs
# to CloudWatch Logs. It's assumed by the ECS service itself, not the container.

resource "aws_iam_role" "task_execution" {
  name               = "${var.project_name}-${var.environment}-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.task_execution_assume_role.json
  description        = "ECS task execution role for ${var.project_name}"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-task-execution-role"
    }
  )
}

# Trust policy allowing ECS tasks to assume this role
data "aws_iam_policy_document" "task_execution_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "task_execution_policy" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws-cn:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional permissions for CloudWatch Logs
resource "aws_iam_role_policy" "task_execution_cloudwatch" {
  name   = "${var.project_name}-${var.environment}-task-execution-cloudwatch"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_cloudwatch.json
}

data "aws_iam_policy_document" "task_execution_cloudwatch" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]

    resources = [
      "arn:aws-cn:logs:*:${var.account_id}:log-group:/ecs/${var.project_name}*",
      "arn:aws-cn:logs:*:${var.account_id}:log-group:/ecs/${var.project_name}*:*"
    ]
  }
}


# ============================================================================
# ECS Task Role
# ============================================================================
# This role is used by the MCP server container to make AWS API calls.
# It's assumed by the application code running inside the container.

resource "aws_iam_role" "task" {
  name               = "${var.project_name}-${var.environment}-task-role"
  assume_role_policy = data.aws_iam_policy_document.task_assume_role.json
  description        = "ECS task role for ${var.project_name} MCP server"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-task-role"
    }
  )
}

# Trust policy allowing ECS tasks to assume this role
data "aws_iam_policy_document" "task_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Attach AWS managed ReadOnlyAccess policy for MCP server
# This provides read-only access to AWS services for the MCP server
resource "aws_iam_role_policy_attachment" "task_readonly" {
  role       = aws_iam_role.task.name
  policy_arn = "arn:aws-cn:iam::aws:policy/ReadOnlyAccess"
}

# ============================================================================
# Cross-Account Assume Role Policy
# ============================================================================
resource "aws_iam_role_policy" "task_cross_account" {
  name   = "${var.project_name}-${var.environment}-task-cross-account"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_cross_account.json
}

data "aws_iam_policy_document" "task_cross_account" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRole"
    ]

    resources = ["*"]
  }
}
