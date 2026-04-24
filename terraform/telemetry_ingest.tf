# =============================================================================
# Telemetry Ingest — real sensor (ESP32 w/ RFID + GPS) → InfluxDB + DynamoDB
# =============================================================================
# Triggered by MQTT topic `coldtrack/sensors/+/data`. The Lambda:
#   1. Resolves RFID uid → batch → active shipment
#   2. Appends a reading to InfluxDB
#   3. Upserts shipment currentTemp/currentLocation/riskLevel in DynamoDB
#   4. Creates an alert row if temp leaves the safe range
#
# Assumes these DynamoDB tables exist:
#   coldtrack-shipments   PK=id
#   coldtrack-alerts      PK=id
#   coldtrack-batches     PK=batchId, GSI `rfidUid-index` on rfidUid
# =============================================================================

data "archive_file" "telemetry_ingest_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/telemetry_ingest"
  output_path = "${path.module}/lambda_packages/telemetry_ingest.zip"
}

resource "aws_lambda_function" "telemetry_ingest" {
  function_name = "${var.project_name}-telemetry-ingest"
  role          = aws_iam_role.telemetry_ingest_role.arn
  runtime       = "python3.12"
  handler       = "index.lambda_handler"
  timeout       = 10
  memory_size   = 256

  filename         = data.archive_file.telemetry_ingest_zip.output_path
  source_code_hash = data.archive_file.telemetry_ingest_zip.output_base64sha256

  environment {
    variables = {
      INFLUX_URL       = var.influx_url
      INFLUX_TOKEN     = var.influx_token
      INFLUX_ORG       = var.influx_org
      INFLUX_BUCKET    = var.influx_bucket
      SHIPMENTS_TABLE  = "coldtrack-shipments"
      ALERTS_TABLE     = "coldtrack-alerts"
      BATCHES_TABLE    = "coldtrack-batches"
      BATCHES_RFID_INDEX = "rfidUid-index"
    }
  }

  tags = { Name = "${var.project_name}-telemetry-ingest" }
}

resource "aws_iam_role" "telemetry_ingest_role" {
  name = "${var.project_name}-telemetry-ingest-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project_name}-telemetry-ingest-role" }
}

resource "aws_iam_role_policy" "telemetry_ingest_policy" {
  name = "${var.project_name}-telemetry-ingest-policy"
  role = aws_iam_role.telemetry_ingest_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/coldtrack-shipments",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/coldtrack-alerts",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/coldtrack-batches",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/coldtrack-batches/index/*"
        ]
      }
    ]
  })
}

resource "aws_iot_topic_rule" "telemetry_ingest" {
  name        = "${replace(var.project_name, "-", "_")}_telemetry_ingest"
  description = "Real ESP32 telemetry (/data topic) → telemetry_ingest Lambda"
  enabled     = true
  sql         = "SELECT *, topic(3) AS topicDeviceId FROM 'coldtrack/sensors/+/data'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.telemetry_ingest.arn
  }

  tags = { Name = "${var.project_name}-telemetry-ingest" }
}

resource "aws_lambda_permission" "allow_iot_invoke_ingest" {
  statement_id  = "AllowExecutionFromIoT"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.telemetry_ingest.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.telemetry_ingest.arn
}
