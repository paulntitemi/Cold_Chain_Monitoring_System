# =============================================================================
# ColdTrack Cold Chain Monitoring System - Main Terraform Configuration
# =============================================================================
# This configuration provisions the complete AWS infrastructure for the
# ColdTrack IoT cold chain monitoring system used for RSV vaccine
# transportation monitoring.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local backend for development
  backend "local" {
    path = "terraform.tfstate"
  }

  # Uncomment the block below to use S3 backend for team/production use:
  # backend "s3" {
  #   bucket         = "coldtrack-terraform-state"
  #   key            = "infrastructure/terraform.tfstate"
  #   region         = "eu-west-1"
  #   encrypt        = true
  #   dynamodb_table = "coldtrack-terraform-locks"
  # }
}

# -----------------------------------------------------------------------------
# AWS Provider Configuration
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Application = "ColdTrack Cold Chain Monitoring"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iot_endpoint" "current" {
  endpoint_type = "iot:Data-ATS"
}
