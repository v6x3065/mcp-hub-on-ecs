terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.80"
    }
  }

  # MVP: Using local state for simplicity
  # For production, consider using S3 backend:
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "aiops-mcp-ecs/terraform.tfstate"
  #   region = "cn-northwest-1"
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
