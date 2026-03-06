# =============================================================================
# ColdTrack Cold Chain Monitoring System - AWS IoT Core Resources
# =============================================================================

# -----------------------------------------------------------------------------
# IoT Thing Type
# -----------------------------------------------------------------------------
resource "aws_iot_thing_type" "esp32_sensor" {
  name = "${var.project_name}-esp32-sensor"

  properties {
    description           = "ColdTrack ESP32-based cold chain temperature sensor"
    searchable_attributes = ["location", "firmware_version"]
  }

  tags = {
    Name = "${var.project_name}-esp32-sensor"
  }
}

# -----------------------------------------------------------------------------
# IoT Things - Individual Sensor Devices
# -----------------------------------------------------------------------------
resource "aws_iot_thing" "sensor" {
  count = var.sensor_count

  name           = format("ESP32_%s_%03d", upper(var.environment), count.index + 1)
  thing_type_name = aws_iot_thing_type.esp32_sensor.name

  attributes = {
    environment = var.environment
    project     = var.project_name
    device_type = "esp32-temperature-sensor"
    index       = tostring(count.index + 1)
  }
}

# -----------------------------------------------------------------------------
# IoT Policy - Sensor Device Permissions
# -----------------------------------------------------------------------------
resource "aws_iot_policy" "sensor_policy" {
  name = "${var.project_name}-sensor-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowConnect"
        Effect = "Allow"
        Action = "iot:Connect"
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:client/$${iot:Connection.Thing.ThingName}"
      },
      {
        Sid    = "AllowPublishTelemetry"
        Effect = "Allow"
        Action = "iot:Publish"
        Resource = [
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/${var.project_name}/sensors/$${iot:Connection.Thing.ThingName}/telemetry",
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/${var.project_name}/sensors/$${iot:Connection.Thing.ThingName}/alerts"
        ]
      },
      {
        Sid    = "AllowSubscribeCommands"
        Effect = "Allow"
        Action = "iot:Subscribe"
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topicfilter/${var.project_name}/commands/$${iot:Connection.Thing.ThingName}"
      },
      {
        Sid    = "AllowReceiveCommands"
        Effect = "Allow"
        Action = "iot:Receive"
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/${var.project_name}/commands/$${iot:Connection.Thing.ThingName}"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-sensor-policy"
  }
}

# -----------------------------------------------------------------------------
# IoT Topic Rule - Route Telemetry Data to Lambda
# -----------------------------------------------------------------------------
resource "aws_iot_topic_rule" "telemetry_to_lambda" {
  name        = "${var.project_name}_telemetry_processing"
  description = "Routes sensor telemetry data to the process-violation Lambda function"
  enabled     = true
  sql         = "SELECT *, topic(3) AS device_id, timestamp() AS server_timestamp FROM '${var.project_name}/sensors/+/telemetry'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.process_violation.arn
  }

  tags = {
    Name = "${var.project_name}-telemetry-to-lambda"
  }
}

# -----------------------------------------------------------------------------
# IoT Topic Rule - Temperature Alert to SNS
# -----------------------------------------------------------------------------
resource "aws_iot_topic_rule" "temperature_alert_to_sns" {
  name        = "${var.project_name}_temperature_alerts"
  description = "Routes temperature violations directly to the SNS critical alerts topic"
  enabled     = true
  sql         = "SELECT *, topic(3) AS device_id, timestamp() AS alert_timestamp FROM '${var.project_name}/sensors/+/telemetry' WHERE temperature > ${var.temp_max} OR temperature < ${var.freeze_threshold}"
  sql_version = "2016-03-23"

  sns {
    message_format = "JSON"
    role_arn       = aws_iam_role.iot_sns_role.arn
    target_arn     = aws_sns_topic.critical_alerts.arn
  }

  tags = {
    Name = "${var.project_name}-temperature-alert-to-sns"
  }
}

# -----------------------------------------------------------------------------
# IoT Topic Rule - Raw Telemetry to Kinesis Firehose → S3
# -----------------------------------------------------------------------------
resource "aws_iot_topic_rule" "telemetry_to_firehose" {
  name        = "${var.project_name}_telemetry_to_firehose"
  description = "Streams all sensor telemetry to Kinesis Firehose for S3 archival and ML training"
  enabled     = true
  sql         = "SELECT * FROM '${var.project_name}/sensors/+/telemetry'"
  sql_version = "2016-03-23"

  firehose {
    delivery_stream_name = aws_kinesis_firehose_delivery_stream.telemetry_to_s3.name
    role_arn             = aws_iam_role.iot_firehose_role.arn
    separator            = "\n"
  }

  error_action {
    cloudwatch_logs {
      log_group_name = "/aws/iot/${var.project_name}-firehose-errors"
      role_arn       = aws_iam_role.iot_firehose_role.arn
    }
  }

  tags = {
    Name = "${var.project_name}-telemetry-to-firehose"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for IoT to deliver to Kinesis Firehose
# -----------------------------------------------------------------------------
resource "aws_iam_role" "iot_firehose_role" {
  name = "${var.project_name}-iot-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-iot-firehose-role"
  }
}

resource "aws_iam_role_policy" "iot_firehose_put" {
  name = "${var.project_name}-iot-firehose-put"
  role = aws_iam_role.iot_firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "firehose:PutRecord"
        Resource = aws_kinesis_firehose_delivery_stream.telemetry_to_s3.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/iot/${var.project_name}-*:*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# IAM Role for IoT to publish to SNS
# -----------------------------------------------------------------------------
resource "aws_iam_role" "iot_sns_role" {
  name = "${var.project_name}-iot-sns-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-iot-sns-role"
  }
}

resource "aws_iam_role_policy" "iot_sns_publish" {
  name = "${var.project_name}-iot-sns-publish"
  role = aws_iam_role.iot_sns_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.critical_alerts.arn
      }
    ]
  })
}
