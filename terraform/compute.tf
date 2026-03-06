# =============================================================================
# ColdTrack Cold Chain Monitoring System - Compute Resources
# =============================================================================

# -----------------------------------------------------------------------------
# IAM Role - Lambda Execution Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-lambda-execution-role"
  }
}

# -----------------------------------------------------------------------------
# IAM Policy - Lambda Permissions
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-*:*"
      },
      {
        Sid    = "TimestreamWrite"
        Effect = "Allow"
        Action = [
          "timestream:WriteRecords",
          "timestream:DescribeEndpoints",
          "timestream:DescribeTable",
          "timestream:DescribeDatabase",
          "timestream:Select"
        ]
        Resource = [
          aws_timestreamwrite_database.telemetry.arn,
          aws_timestreamwrite_table.sensor_data.arn
        ]
      },
      {
        Sid    = "TimestreamDescribeEndpoints"
        Effect = "Allow"
        Action = "timestream:DescribeEndpoints"
        Resource = "*"
      },
      {
        Sid    = "IoTPublish"
        Effect = "Allow"
        Action = [
          "iot:Publish",
          "iot:DescribeEndpoint"
        ]
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/${var.project_name}/*"
      },
      {
        Sid    = "SNSPublish"
        Effect = "Allow"
        Action = "sns:Publish"
        Resource = aws_sns_topic.critical_alerts.arn
      },
      {
        Sid    = "S3Read"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.lambda_packages.arn,
          "${aws_s3_bucket.lambda_packages.arn}/*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Lambda Function - Process Violation
# -----------------------------------------------------------------------------
# Placeholder zip for initial deployment. Replace with actual deployment package.
data "archive_file" "lambda_placeholder" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/placeholder.zip"

  source {
    content  = <<-EOF
      def lambda_handler(event, context):
          """Placeholder handler - replace with actual deployment package."""
          return {"statusCode": 200, "body": "ColdTrack placeholder"}
    EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "process_violation" {
  function_name = "${var.project_name}-process-violation"
  description   = "Processes incoming sensor telemetry and detects temperature violations"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.11"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory
  filename      = data.archive_file.lambda_placeholder.output_path

  environment {
    variables = {
      PROJECT_NAME         = var.project_name
      ENVIRONMENT          = var.environment
      TEMP_MIN             = tostring(var.temp_min)
      TEMP_MAX             = tostring(var.temp_max)
      FREEZE_THRESHOLD     = tostring(var.freeze_threshold)
      SNS_TOPIC_ARN        = aws_sns_topic.critical_alerts.arn
      TIMESTREAM_DB        = aws_timestreamwrite_database.telemetry.database_name
      TIMESTREAM_TABLE     = aws_timestreamwrite_table.sensor_data.table_name
      INFLUX_URL           = var.influx_url
      INFLUX_TOKEN         = var.influx_token
      INFLUX_ORG           = var.influx_org
      INFLUX_BUCKET        = var.influx_bucket
    }
  }

  tags = {
    Name     = "${var.project_name}-process-violation"
    Function = "telemetry-processing"
  }
}

# -----------------------------------------------------------------------------
# Lambda Function - Predictive Analytics
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "predictive_analytics" {
  function_name = "${var.project_name}-predictive-analytics"
  description   = "Runs predictive analytics on sensor data to forecast potential violations"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.11"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory
  filename      = data.archive_file.lambda_placeholder.output_path

  environment {
    variables = {
      PROJECT_NAME         = var.project_name
      ENVIRONMENT          = var.environment
      TEMP_MIN             = tostring(var.temp_min)
      TEMP_MAX             = tostring(var.temp_max)
      FREEZE_THRESHOLD     = tostring(var.freeze_threshold)
      SNS_TOPIC_ARN        = aws_sns_topic.critical_alerts.arn
      TIMESTREAM_DB        = aws_timestreamwrite_database.telemetry.database_name
      TIMESTREAM_TABLE     = aws_timestreamwrite_table.sensor_data.table_name
      INFLUX_URL           = var.influx_url
      INFLUX_TOKEN         = var.influx_token
      INFLUX_ORG           = var.influx_org
      INFLUX_BUCKET        = var.influx_bucket
    }
  }

  tags = {
    Name     = "${var.project_name}-predictive-analytics"
    Function = "predictive-analytics"
  }
}

# -----------------------------------------------------------------------------
# Lambda Function - Blockchain Logger
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "blockchain_logger" {
  function_name = "${var.project_name}-blockchain-logger"
  description   = "Logs immutable audit records of temperature events for compliance"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.11"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory
  filename      = data.archive_file.lambda_placeholder.output_path

  environment {
    variables = {
      PROJECT_NAME         = var.project_name
      ENVIRONMENT          = var.environment
      TIMESTREAM_DB        = aws_timestreamwrite_database.telemetry.database_name
      TIMESTREAM_TABLE     = aws_timestreamwrite_table.sensor_data.table_name
      INFLUX_URL           = var.influx_url
      INFLUX_TOKEN         = var.influx_token
      INFLUX_ORG           = var.influx_org
      INFLUX_BUCKET        = var.influx_bucket
    }
  }

  tags = {
    Name     = "${var.project_name}-blockchain-logger"
    Function = "blockchain-logging"
  }
}

# -----------------------------------------------------------------------------
# Lambda Function - API Handler
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "api_handler" {
  function_name = "${var.project_name}-api-handler"
  description   = "Handles REST API requests for the ColdTrack dashboard and integrations"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.11"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory
  filename      = data.archive_file.lambda_placeholder.output_path

  environment {
    variables = {
      PROJECT_NAME         = var.project_name
      ENVIRONMENT          = var.environment
      TEMP_MIN             = tostring(var.temp_min)
      TEMP_MAX             = tostring(var.temp_max)
      FREEZE_THRESHOLD     = tostring(var.freeze_threshold)
      IOT_ENDPOINT         = data.aws_iot_endpoint.current.endpoint_address
      SNS_TOPIC_ARN        = aws_sns_topic.critical_alerts.arn
      TIMESTREAM_DB        = aws_timestreamwrite_database.telemetry.database_name
      TIMESTREAM_TABLE     = aws_timestreamwrite_table.sensor_data.table_name
      INFLUX_URL           = var.influx_url
      INFLUX_TOKEN         = var.influx_token
      INFLUX_ORG           = var.influx_org
      INFLUX_BUCKET        = var.influx_bucket
    }
  }

  tags = {
    Name     = "${var.project_name}-api-handler"
    Function = "api-handler"
  }
}

# -----------------------------------------------------------------------------
# Lambda Permissions
# -----------------------------------------------------------------------------

# Allow IoT Core to invoke the process-violation function
resource "aws_lambda_permission" "iot_invoke_process_violation" {
  statement_id  = "AllowIoTInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_violation.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.telemetry_to_lambda.arn
}

# Allow API Gateway to invoke the api-handler function
resource "aws_lambda_permission" "apigw_invoke_api_handler" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.coldtrack_api.execution_arn}/*/*"
}

# -----------------------------------------------------------------------------
# SNS Topic - Critical Alerts
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "critical_alerts" {
  name = "${var.project_name}-critical-alerts"

  tags = {
    Name = "${var.project_name}-critical-alerts"
  }
}

# -----------------------------------------------------------------------------
# SNS Subscription - Email Alerts
# -----------------------------------------------------------------------------
resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.critical_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# -----------------------------------------------------------------------------
# SNS Subscription - SMS Alerts (conditional on alert_phone being set)
# -----------------------------------------------------------------------------
resource "aws_sns_topic_subscription" "sms_alert" {
  count = var.alert_phone != "" ? 1 : 0

  topic_arn = aws_sns_topic.critical_alerts.arn
  protocol  = "sms"
  endpoint  = var.alert_phone
}
