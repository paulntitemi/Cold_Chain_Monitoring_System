# =============================================================================
# Dashboard + Rider API — single Lambda serving every endpoint the /web
# dashboard and /mobile/coldtrack-pwa call. Backed by DynamoDB tables
# populated by telemetry_ingest + user actions.
# =============================================================================

data "archive_file" "dashboard_api_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/dashboard_api"
  output_path = "${path.module}/lambda_packages/dashboard_api.zip"
}

resource "aws_lambda_function" "dashboard_api" {
  function_name = "${var.project_name}-dashboard-api"
  role          = aws_iam_role.dashboard_api_role.arn
  runtime       = "python3.12"
  handler       = "index.lambda_handler"
  timeout       = 10
  memory_size   = 256

  filename         = data.archive_file.dashboard_api_zip.output_path
  source_code_hash = data.archive_file.dashboard_api_zip.output_base64sha256

  environment {
    variables = {
      SHIPMENTS_TABLE       = "coldtrack-shipments"
      ALERTS_TABLE          = "coldtrack-alerts"
      BATCHES_TABLE         = "coldtrack-batches"
      RIDERS_TABLE          = "coldtrack-riders"
      HANDOFFS_TABLE        = "coldtrack-handoffs"
      STORAGE_CENTRES_TABLE = "coldtrack-storage-centres"
      DEFAULT_RIDER_ID      = "R-006"
      # InfluxDB read access — hydrates Shipment.temperatureHistory at
      # read time so charts survive page reloads. Falls back to empty
      # history if unset; non-essential for correctness.
      INFLUX_URL            = var.influx_url
      INFLUX_TOKEN          = var.influx_token
      INFLUX_ORG            = var.influx_org
      INFLUX_BUCKET         = var.influx_bucket
      INFLUX_HISTORY_HOURS  = "2"
      INFLUX_HISTORY_LIMIT  = "200"
    }
  }

  tags = { Name = "${var.project_name}-dashboard-api" }
}

resource "aws_iam_role" "dashboard_api_role" {
  name = "${var.project_name}-dashboard-api-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "dashboard_api_policy" {
  name = "${var.project_name}-dashboard-api-policy"
  role = aws_iam_role.dashboard_api_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/coldtrack-shipments",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/coldtrack-alerts",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/coldtrack-batches",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/coldtrack-riders",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/coldtrack-handoffs",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/coldtrack-storage-centres",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/coldtrack-*/index/*"
        ]
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# API Gateway integration + routes
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_integration" "dashboard_api" {
  api_id                 = aws_apigatewayv2_api.coldtrack_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dashboard_api.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Route declarations — one per (method, path) pair. HTTP API v2 handles
# CORS preflight automatically at the API level (cors_configuration in
# api.tf), so no OPTIONS routes are needed.
locals {
  dashboard_routes = [
    "GET /fleet/active",
    "GET /shipments/{id}",
    "POST /shipments/{id}/start",
    "POST /shipments/{id}/ping",
    "GET /batches",
    "GET /batches/{id}",
    "POST /batches",
    "PATCH /batches/{id}",
    "GET /alerts",
    "GET /alerts/active",
    "PATCH /alerts/{id}",
    "POST /incidents",
    "GET /riders",
    "GET /riders/me",
    "GET /riders/me/shipment",
    "GET /riders/me/alerts",
    "GET /riders/me/assignments",
    "POST /handoffs",
    "GET /storage-centres",
  ]
}

resource "aws_apigatewayv2_route" "dashboard_api" {
  for_each = toset(local.dashboard_routes)

  api_id    = aws_apigatewayv2_api.coldtrack_api.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.dashboard_api.id}"

  # Phase 1 guest access — uses Cognito Identity Pool credentials already,
  # but we leave auth open on the routes themselves for now so the browser's
  # unsigned CORS preflight can reach the API. Tighten to AWS_IAM in Phase 2.
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "allow_apigw_invoke_dashboard" {
  statement_id  = "AllowExecutionFromAPIGatewayDashboard"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dashboard_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.coldtrack_api.execution_arn}/*/*"
}
