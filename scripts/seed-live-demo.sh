#!/usr/bin/env bash
# =============================================================================
# Seed DynamoDB with a batch (RFID 08:1A:4F:44), shipment, rider so the real
# ESP32 publishing on coldtrack/sensors/ESP32_TMP102_GPS_RFID_01/data has a
# destination row in the dashboard.
#
# Run this ONCE after creating the tables. Uses AWS CLI + the current default
# profile/region.
# =============================================================================
set -euo pipefail

REGION="${AWS_REGION:-eu-west-1}"

echo "Seeding coldtrack-riders..."
aws dynamodb put-item --region "$REGION" --table-name coldtrack-riders --item '{
  "id":                 {"S": "R-006"},
  "name":               {"S": "Jake Fletcher"},
  "phone":              {"S": "+447700900006"},
  "vehicleType":        {"S": "motorbike"},
  "activeShipmentId":   {"S": "SHIP-DEV-0001"},
  "totalTrips":         {"N": "71"},
  "alertResponseRate":  {"N": "0.6"}
}'

echo "Seeding coldtrack-batches (with rfidUid 08:1A:4F:44)..."
aws dynamodb put-item --region "$REGION" --table-name coldtrack-batches --item '{
  "batchId":             {"S": "YFV-2024-UK-0008"},
  "rfidUid":             {"S": "08:1A:4F:44"},
  "vaccineType":         {"S": "Yellow Fever"},
  "manufacturer":        {"S": "Sanofi Pasteur"},
  "doseCount":           {"N": "300"},
  "dosesRemaining":      {"N": "300"},
  "minSafeTemp":         {"N": "2.0"},
  "maxSafeTemp":         {"N": "8.0"},
  "vvmStatus":           {"S": "stage1"},
  "status":              {"S": "in_transit"},
  "currentShipmentId":   {"S": "SHIP-DEV-0001"},
  "totalExcursionMinutes": {"N": "0"}
}'

echo "Seeding coldtrack-shipments..."
aws dynamodb put-item --region "$REGION" --table-name coldtrack-shipments --item '{
  "id":                    {"S": "SHIP-DEV-0001"},
  "deviceId":              {"S": "ESP32_TMP102_GPS_RFID_01"},
  "riderId":               {"S": "R-006"},
  "riderName":             {"S": "Jake Fletcher"},
  "riderPhone":            {"S": "+447700900006"},
  "batchIds":              {"L": [{"S": "YFV-2024-UK-0008"}]},
  "origin":                {"S": "King'\''s College Hospital"},
  "destination":           {"S": "Queen Elizabeth Hospital Woolwich"},
  "status":                {"S": "active"},
  "currentTemp":           {"N": "23.4"},
  "minSafeTemp":           {"N": "2.0"},
  "maxSafeTemp":           {"N": "8.0"},
  "riskScore":             {"N": "0.92"},
  "riskLevel":             {"S": "critical"},
  "remainingSafeMinutes":  {"N": "1"},
  "secondsOutsideRange":   {"N": "0"},
  "currentLocation":       {"M": {"lat": {"N": "51.4681"}, "lng": {"N": "-0.0933"}}},
  "destinationLocation":   {"M": {"lat": {"N": "51.4948"}, "lng": {"N": "0.0601"}}},
  "startTime":             {"S": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"},
  "estimatedArrival":      {"S": "'"$(date -u -v+50M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+50 minutes' +%Y-%m-%dT%H:%M:%SZ)"'"},
  "lastUpdated":           {"S": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}
}'

echo ""
echo "Done. The dashboard should show SHIP-DEV-0001 once the IoT Rule + Lambda"
echo "are active and the ESP32 publishes its next reading."
