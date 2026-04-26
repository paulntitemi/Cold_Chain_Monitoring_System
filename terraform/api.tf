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
    # "*" lets the browser preflight approve SigV4 headers (x-amz-date, etc.)
    # sent by the dashboard + PWA. PATCH added for alert/batch updates.
    allow_headers = ["*"]
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
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

# The old api_handler integration + /devices* routes have been removed.
# All dashboard + rider routes now live in terraform/dashboard_api.tf
# behind a single Lambda (coldtrack-dashboard-api). If admin-style device
# endpoints are needed later, add them there or in a new file.
