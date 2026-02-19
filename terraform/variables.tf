# =============================================================================
# ColdTrack Cold Chain Monitoring System - Variable Definitions
# =============================================================================

# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Deployment environment (development, staging, production)"
  type        = string
  default     = "development"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "coldtrack"
}

# -----------------------------------------------------------------------------
# IoT / Sensor Configuration
# -----------------------------------------------------------------------------
variable "sensor_count" {
  description = "Number of ESP32 sensor devices to provision"
  type        = number
  default     = 10

  validation {
    condition     = var.sensor_count >= 1 && var.sensor_count <= 100
    error_message = "Sensor count must be between 1 and 100."
  }
}

# -----------------------------------------------------------------------------
# Temperature Thresholds (Celsius)
# -----------------------------------------------------------------------------
variable "temp_min" {
  description = "Minimum acceptable temperature in Celsius (WHO guideline for vaccines)"
  type        = number
  default     = 2.0
}

variable "temp_max" {
  description = "Maximum acceptable temperature in Celsius (WHO guideline for vaccines)"
  type        = number
  default     = 8.0
}

variable "freeze_threshold" {
  description = "Temperature below which a freeze alert is triggered"
  type        = number
  default     = 0.0
}

# -----------------------------------------------------------------------------
# Alert Configuration
# -----------------------------------------------------------------------------
variable "alert_email" {
  description = "Email address for critical temperature alerts via SNS"
  type        = string
  sensitive   = true
}

variable "alert_phone" {
  description = "Phone number (E.164 format, e.g. +27821234567) for SMS alerts. Leave empty to disable SMS."
  type        = string
  default     = ""
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Lambda Configuration
# -----------------------------------------------------------------------------
variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory" {
  description = "Memory allocation in MB for Lambda functions"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory >= 128 && var.lambda_memory <= 3008
    error_message = "Lambda memory must be between 128 and 3008 MB."
  }
}

# -----------------------------------------------------------------------------
# InfluxDB Configuration (for Lambda environment variables)
# -----------------------------------------------------------------------------
variable "influx_url" {
  description = "InfluxDB connection URL"
  type        = string
  default     = "http://localhost:8086"
}

variable "influx_token" {
  description = "InfluxDB authentication token"
  type        = string
  default     = "coldtrack-super-secret-token-change-in-production"
  sensitive   = true
}

variable "influx_org" {
  description = "InfluxDB organization name"
  type        = string
  default     = "coldtrack"
}

variable "influx_bucket" {
  description = "InfluxDB bucket name for sensor data"
  type        = string
  default     = "sensors"
}
