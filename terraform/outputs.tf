# =============================================================================
# ColdTrack Cold Chain Monitoring System - Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# IoT Core
# -----------------------------------------------------------------------------
output "iot_endpoint" {
  description = "AWS IoT Core data endpoint for MQTT connections"
  value       = data.aws_iot_endpoint.current.endpoint_address
}

# -----------------------------------------------------------------------------
# Lambda Functions
# -----------------------------------------------------------------------------
output "lambda_function_arns" {
  description = "ARNs of all deployed Lambda functions"
  value = {
    process_violation    = aws_lambda_function.process_violation.arn
    predictive_analytics = aws_lambda_function.predictive_analytics.arn
    blockchain_logger    = aws_lambda_function.blockchain_logger.arn
    api_handler          = aws_lambda_function.api_handler.arn
  }
}

# -----------------------------------------------------------------------------
# SNS
# -----------------------------------------------------------------------------
output "sns_topic_arn" {
  description = "ARN of the SNS topic for critical temperature alerts"
  value       = aws_sns_topic.critical_alerts.arn
}

# -----------------------------------------------------------------------------
# API Gateway
# -----------------------------------------------------------------------------
output "api_gateway_url" {
  description = "Base URL of the ColdTrack HTTP API"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

# -----------------------------------------------------------------------------
# S3
# -----------------------------------------------------------------------------
output "s3_bucket_name" {
  description = "Name of the S3 bucket for Lambda deployment packages"
  value       = aws_s3_bucket.lambda_packages.id
}

output "s3_raw_data_bucket" {
  description = "Name of the S3 bucket for raw telemetry data and ML training datasets"
  value       = aws_s3_bucket.raw_data.id
}

output "s3_ml_models_bucket" {
  description = "Name of the S3 bucket for ML model artifacts"
  value       = aws_s3_bucket.ml_models.id
}

# -----------------------------------------------------------------------------
# Kinesis Firehose
# -----------------------------------------------------------------------------
output "firehose_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream (IoT → S3)"
  value       = aws_kinesis_firehose_delivery_stream.telemetry_to_s3.name
}

output "firehose_stream_arn" {
  description = "ARN of the Kinesis Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.telemetry_to_s3.arn
}

# Timestream outputs removed — we use InfluxDB for time-series data.
