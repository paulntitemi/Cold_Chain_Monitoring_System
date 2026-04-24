# =============================================================================
# ColdTrack Cold Chain Monitoring System - Storage Resources
# =============================================================================

# Timestream for LiveAnalytics is no longer accepting new AWS customers
# (as of 2025). We use InfluxDB for time-series telemetry instead — the
# telemetry_ingest Lambda writes points via the Influx HTTP API. The S3
# raw-data bucket below still serves as the long-term archive via Firehose.

# -----------------------------------------------------------------------------
# S3 Bucket - Raw Telemetry Data (ML training + long-term archive)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "raw_data" {
  bucket = "${var.project_name}-raw-data-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  tags = {
    Name    = "${var.project_name}-raw-data"
    Purpose = "telemetry-archive-ml-training"
  }
}

resource "aws_s3_bucket_versioning" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id
  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "raw_data" {
  bucket                  = aws_s3_bucket.raw_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  rule {
    id     = "telemetry-tiering"
    status = "Enabled"

    filter {
      prefix = "telemetry/"
    }

    # Move to Intelligent-Tiering after 30 days (auto-adjusts based on access)
    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }

    # Move to Glacier after 90 days (cheap long-term storage for ML datasets)
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete after 2 years
    expiration {
      days = 730
    }
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket - ML Model Artifacts
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "ml_models" {
  bucket = "${var.project_name}-ml-models-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  tags = {
    Name    = "${var.project_name}-ml-models"
    Purpose = "machine-learning-model-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "ml_models" {
  bucket = aws_s3_bucket.ml_models.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ml_models" {
  bucket = aws_s3_bucket.ml_models.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "ml_models" {
  bucket                  = aws_s3_bucket.ml_models.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# IAM Role - Kinesis Firehose → S3
# -----------------------------------------------------------------------------
resource "aws_iam_role" "firehose_role" {
  name = "${var.project_name}-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-firehose-role"
  }
}

resource "aws_iam_role_policy" "firehose_s3_policy" {
  name = "${var.project_name}-firehose-s3-policy"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Write"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.raw_data.arn,
          "${aws_s3_bucket.raw_data.arn}/*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/${var.project_name}-*:*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Kinesis Firehose - Telemetry → S3 (batched, partitioned by date)
# -----------------------------------------------------------------------------
resource "aws_kinesis_firehose_delivery_stream" "telemetry_to_s3" {
  name        = "${var.project_name}-telemetry-to-s3"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.raw_data.arn

    # Partition by date for easy ML dataset slicing
    prefix              = "telemetry/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"

    # Buffer: flush every 5 minutes or 64 MB — whichever comes first
    buffering_interval = 300
    buffering_size     = 64

    compression_format = "GZIP"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = "/aws/kinesisfirehose/${var.project_name}-telemetry-to-s3"
      log_stream_name = "S3Delivery"
    }
  }

  tags = {
    Name    = "${var.project_name}-telemetry-to-s3"
    Purpose = "raw-telemetry-archive"
  }
}

# -----------------------------------------------------------------------------
# Lambda permissions: allow writing raw events to S3
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "lambda_raw_data_s3" {
  name = "${var.project_name}-lambda-raw-data-s3"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RawDataS3Write"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw_data.arn,
          "${aws_s3_bucket.raw_data.arn}/*"
        ]
      },
      {
        Sid    = "MLModelsS3ReadWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.ml_models.arn,
          "${aws_s3_bucket.ml_models.arn}/*"
        ]
      }
    ]
  })
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
