# =============================================================================
# ColdTrack Cold Chain Monitoring System - API Gateway Resources
# =============================================================================

# -----------------------------------------------------------------------------
# HTTP API
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "coldtrack_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  description   = "ColdTrack Cold Chain Monitoring REST API"

  cors_configuration {
    allow_headers = ["Content-Type", "Authorization", "X-Api-Key"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 3600
  }

  tags = {
    Name = "${var.project_name}-api"
  }
}

# -----------------------------------------------------------------------------
# Default Stage (auto-deploy enabled)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.coldtrack_api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }

  tags = {
    Name = "${var.project_name}-api-default-stage"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for API Gateway Access Logs
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}-api"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-api-logs"
  }
}

# -----------------------------------------------------------------------------
# Lambda Integration (proxy)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "lambda_api_handler" {
  api_id                 = aws_apigatewayv2_api.coldtrack_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api_handler.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# -----------------------------------------------------------------------------
# Routes
# -----------------------------------------------------------------------------

# GET /devices - List all registered devices
resource "aws_apigatewayv2_route" "get_devices" {
  api_id    = aws_apigatewayv2_api.coldtrack_api.id
  route_key = "GET /devices"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_api_handler.id}"
}

# GET /devices/{deviceId} - Get details for a specific device
resource "aws_apigatewayv2_route" "get_device" {
  api_id    = aws_apigatewayv2_api.coldtrack_api.id
  route_key = "GET /devices/{deviceId}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_api_handler.id}"
}

# GET /devices/{deviceId}/telemetry - Get telemetry data for a device
resource "aws_apigatewayv2_route" "get_device_telemetry" {
  api_id    = aws_apigatewayv2_api.coldtrack_api.id
  route_key = "GET /devices/{deviceId}/telemetry"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_api_handler.id}"
}

# GET /alerts - List all temperature alerts
resource "aws_apigatewayv2_route" "get_alerts" {
  api_id    = aws_apigatewayv2_api.coldtrack_api.id
  route_key = "GET /alerts"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_api_handler.id}"
}

# POST /devices/{deviceId}/commands - Send a command to a specific device
resource "aws_apigatewayv2_route" "post_device_commands" {
  api_id    = aws_apigatewayv2_api.coldtrack_api.id
  route_key = "POST /devices/{deviceId}/commands"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_api_handler.id}"
}
