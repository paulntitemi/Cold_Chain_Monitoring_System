# =============================================================================
# DynamoDB tables backing the dashboard + rider PWA.
# All on-demand billing (pay-per-request) — traffic is tiny, predictable
# latency, no capacity planning needed.
# =============================================================================

# ---------- Shipments ----------
resource "aws_dynamodb_table" "shipments" {
  name         = "coldtrack-shipments"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "riderId"
    type = "S"
  }

  attribute {
    name = "deviceId"
    type = "S"
  }

  # GSI for /riders/me/shipment lookup
  global_secondary_index {
    name            = "riderId-index"
    hash_key        = "riderId"
    projection_type = "ALL"
  }

  # GSI for looking up a shipment by its paired sensor
  global_secondary_index {
    name            = "deviceId-index"
    hash_key        = "deviceId"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "coldtrack-shipments" }
}

# ---------- Alerts ----------
resource "aws_dynamodb_table" "alerts" {
  name         = "coldtrack-alerts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "shipmentId"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  # GSI for /alerts/active and for joining alerts to a shipment
  global_secondary_index {
    name            = "shipmentId-index"
    hash_key        = "shipmentId"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "coldtrack-alerts" }
}

# ---------- Batches ----------
resource "aws_dynamodb_table" "batches" {
  name         = "coldtrack-batches"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "batchId"

  attribute {
    name = "batchId"
    type = "S"
  }

  attribute {
    name = "rfidUid"
    type = "S"
  }

  # GSI used by telemetry_ingest Lambda: RFID uid → batch → shipment
  global_secondary_index {
    name            = "rfidUid-index"
    hash_key        = "rfidUid"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "coldtrack-batches" }
}

# ---------- Riders ----------
resource "aws_dynamodb_table" "riders" {
  name         = "coldtrack-riders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "coldtrack-riders" }
}

# ---------- Handoffs ----------
resource "aws_dynamodb_table" "handoffs" {
  name         = "coldtrack-handoffs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "shipmentId"
    type = "S"
  }

  global_secondary_index {
    name            = "shipmentId-index"
    hash_key        = "shipmentId"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "coldtrack-handoffs" }
}

# ---------- Storage centres (optional — the PWA's Diversion screen uses this) ----------
resource "aws_dynamodb_table" "storage_centres" {
  name         = "coldtrack-storage-centres"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = { Name = "coldtrack-storage-centres" }
}
