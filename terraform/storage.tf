# =============================================================================
# ColdTrack Cold Chain Monitoring System - Storage Resources
# =============================================================================

# -----------------------------------------------------------------------------
# Amazon Timestream Database
# -----------------------------------------------------------------------------
resource "aws_timestreamwrite_database" "telemetry" {
  database_name = "${var.project_name}-telemetry"

  tags = {
    Name = "${var.project_name}-telemetry"
  }
}

# -----------------------------------------------------------------------------
# Amazon Timestream Table - Sensor Data
# -----------------------------------------------------------------------------
resource "aws_timestreamwrite_table" "sensor_data" {
  database_name = aws_timestreamwrite_database.telemetry.database_name
  table_name    = "sensor_data"

  retention_properties {
    # In-memory store: 90 days for fast queries on recent data
    memory_store_retention_period_in_hours = 2160 # 90 days

    # Magnetic store: 1 year for historical analysis and compliance
    magnetic_store_retention_period_in_days = 365
  }

  magnetic_store_write_properties {
    enable_magnetic_store_writes = true
  }

  tags = {
    Name = "${var.project_name}-sensor-data"
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket - Lambda Deployment Packages
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "lambda_packages" {
  bucket = "${var.project_name}-lambda-packages-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  tags = {
    Name = "${var.project_name}-lambda-packages"
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket Versioning
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "lambda_packages" {
  bucket = aws_s3_bucket.lambda_packages.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket Server-Side Encryption
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_packages" {
  bucket = aws_s3_bucket.lambda_packages.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket Public Access Block
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "lambda_packages" {
  bucket = aws_s3_bucket.lambda_packages.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
