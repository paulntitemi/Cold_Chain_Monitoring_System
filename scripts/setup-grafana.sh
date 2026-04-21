#!/usr/bin/env bash
# =============================================================================
# ColdTrack - Grafana Setup (Docker)
# Runs Grafana locally with the Amazon Timestream plugin pre-installed.
#
# Prerequisites:
#   - Docker installed and running
#   - AWS credentials with Timestream read access
#
# Usage:
#   export AWS_ACCESS_KEY_ID=your_key
#   export AWS_SECRET_ACCESS_KEY=your_secret
#   ./scripts/setup-grafana.sh
#
# Grafana will be available at: http://localhost:3000
#   Default login: admin / coldtrack
# =============================================================================
set -euo pipefail

REGION="eu-west-1"
GRAFANA_PORT=3000
GRAFANA_PASSWORD="coldtrack"
CONTAINER_NAME="coldtrack-grafana"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

pass()  { echo -e "${GREEN}[PASS]${NC} $1"; }
info()  { echo -e "${YELLOW}[INFO]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; }

echo -e "\n${GREEN}============================================================${NC}"
echo -e "  ColdTrack Grafana Setup"
echo -e "${GREEN}============================================================${NC}"

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
    fail "Docker not found. Install: https://docs.docker.com/get-docker/"
    exit 1
fi
pass "Docker found"

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    fail "AWS credentials not set. Export AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY."
    exit 1
fi
pass "AWS credentials set"

# ---------------------------------------------------------------------------
# Stop existing container if running
# ---------------------------------------------------------------------------
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    info "Stopping existing Grafana container..."
    docker stop "$CONTAINER_NAME" &>/dev/null || true
    docker rm "$CONTAINER_NAME" &>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Create provisioning directory for Timestream datasource
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GRAFANA_DIR="${PROJECT_DIR}/grafana"
PROVISIONING_DIR="${GRAFANA_DIR}/provisioning"

mkdir -p "${PROVISIONING_DIR}/datasources"
mkdir -p "${PROVISIONING_DIR}/dashboards"
mkdir -p "${GRAFANA_DIR}/dashboards"

# Auto-configure Timestream datasource
cat > "${PROVISIONING_DIR}/datasources/timestream.yml" << EOF
apiVersion: 1

datasources:
  - name: Amazon Timestream
    type: grafana-timestream-datasource
    access: proxy
    isDefault: true
    jsonData:
      authType: keys
      defaultRegion: ${REGION}
      defaultDatabase: coldtrack-telemetry
      defaultTable: sensor_data
      defaultMeasure: temperature
    secureJsonData:
      accessKey: ${AWS_ACCESS_KEY_ID}
      secretKey: ${AWS_SECRET_ACCESS_KEY}
    editable: true
EOF

# Dashboard provisioning config
cat > "${PROVISIONING_DIR}/dashboards/coldtrack.yml" << EOF
apiVersion: 1

providers:
  - name: ColdTrack
    orgId: 1
    folder: ColdTrack
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: false
EOF

pass "Grafana provisioning configured"

# ---------------------------------------------------------------------------
# Create ColdTrack dashboard JSON
# ---------------------------------------------------------------------------
cat > "${GRAFANA_DIR}/dashboards/coldtrack-overview.json" << 'DASHBOARD_EOF'
{
  "dashboard": {
    "id": null,
    "uid": "coldtrack-overview",
    "title": "ColdTrack - Cold Chain Monitoring",
    "tags": ["coldtrack", "iot", "vaccine"],
    "timezone": "browser",
    "refresh": "10s",
    "time": { "from": "now-1h", "to": "now" },
    "panels": [
      {
        "id": 1,
        "title": "Temperature (°C)",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
        "datasource": { "type": "grafana-timestream-datasource", "uid": "" },
        "targets": [{
          "rawQuery": true,
          "queryString": "SELECT time, device_id, measure_value::double AS temperature FROM \"coldtrack-telemetry\".\"sensor_data\" WHERE measure_name = 'temperature' AND time >= ago(1h) ORDER BY time DESC"
        }],
        "fieldConfig": {
          "defaults": {
            "color": { "mode": "palette-classic" },
            "custom": {
              "lineWidth": 2,
              "fillOpacity": 10,
              "thresholdsStyle": { "mode": "area" }
            },
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "value": null, "color": "blue" },
                { "value": 0, "color": "red" },
                { "value": 2, "color": "green" },
                { "value": 8, "color": "orange" },
                { "value": 10, "color": "red" }
              ]
            },
            "unit": "celsius",
            "min": -5,
            "max": 15
          }
        },
        "options": {
          "legend": { "displayMode": "table", "placement": "bottom", "calcs": ["mean", "min", "max", "lastNotNull"] }
        }
      },
      {
        "id": 2,
        "title": "Humidity (%)",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
        "datasource": { "type": "grafana-timestream-datasource", "uid": "" },
        "targets": [{
          "rawQuery": true,
          "queryString": "SELECT time, device_id, measure_value::double AS humidity FROM \"coldtrack-telemetry\".\"sensor_data\" WHERE measure_name = 'humidity' AND time >= ago(1h) ORDER BY time DESC"
        }],
        "fieldConfig": {
          "defaults": {
            "color": { "mode": "palette-classic" },
            "custom": { "lineWidth": 2, "fillOpacity": 10 },
            "unit": "percent",
            "min": 0,
            "max": 100
          }
        }
      },
      {
        "id": 3,
        "title": "Battery Level (%)",
        "type": "gauge",
        "gridPos": { "h": 8, "w": 6, "x": 0, "y": 8 },
        "datasource": { "type": "grafana-timestream-datasource", "uid": "" },
        "targets": [{
          "rawQuery": true,
          "queryString": "SELECT device_id, measure_value::double AS battery FROM \"coldtrack-telemetry\".\"sensor_data\" WHERE measure_name = 'battery' AND time >= ago(5m) ORDER BY time DESC LIMIT 1"
        }],
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "min": 0,
            "max": 100,
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "value": null, "color": "red" },
                { "value": 10, "color": "orange" },
                { "value": 20, "color": "yellow" },
                { "value": 50, "color": "green" }
              ]
            }
          }
        }
      },
      {
        "id": 4,
        "title": "RSSI Signal Strength (dBm)",
        "type": "stat",
        "gridPos": { "h": 8, "w": 6, "x": 6, "y": 8 },
        "datasource": { "type": "grafana-timestream-datasource", "uid": "" },
        "targets": [{
          "rawQuery": true,
          "queryString": "SELECT device_id, measure_value::double AS rssi FROM \"coldtrack-telemetry\".\"sensor_data\" WHERE measure_name = 'rssi' AND time >= ago(5m) ORDER BY time DESC LIMIT 1"
        }],
        "fieldConfig": {
          "defaults": {
            "unit": "dBm",
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "value": null, "color": "red" },
                { "value": -80, "color": "orange" },
                { "value": -60, "color": "green" }
              ]
            }
          }
        }
      },
      {
        "id": 5,
        "title": "Temperature Safe Range Compliance",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 12, "x": 12, "y": 8 },
        "datasource": { "type": "grafana-timestream-datasource", "uid": "" },
        "targets": [{
          "rawQuery": true,
          "queryString": "SELECT BIN(time, 5m) AS binned_time, device_id, AVG(measure_value::double) AS avg_temp, MIN(measure_value::double) AS min_temp, MAX(measure_value::double) AS max_temp FROM \"coldtrack-telemetry\".\"sensor_data\" WHERE measure_name = 'temperature' AND time >= ago(6h) GROUP BY BIN(time, 5m), device_id ORDER BY binned_time DESC"
        }],
        "fieldConfig": {
          "defaults": {
            "unit": "celsius",
            "custom": { "lineWidth": 2, "fillOpacity": 5 }
          }
        },
        "options": {
          "legend": { "displayMode": "table", "placement": "bottom", "calcs": ["mean", "min", "max"] }
        }
      },
      {
        "id": 6,
        "title": "All Measures - Raw Data Table",
        "type": "table",
        "gridPos": { "h": 8, "w": 24, "x": 0, "y": 16 },
        "datasource": { "type": "grafana-timestream-datasource", "uid": "" },
        "targets": [{
          "rawQuery": true,
          "queryString": "SELECT time, device_id, measure_name, measure_value::double FROM \"coldtrack-telemetry\".\"sensor_data\" WHERE time >= ago(30m) ORDER BY time DESC LIMIT 50"
        }]
      }
    ]
  },
  "overwrite": true
}
DASHBOARD_EOF

pass "ColdTrack dashboard created"

# ---------------------------------------------------------------------------
# Run Grafana container
# ---------------------------------------------------------------------------
info "Starting Grafana container..."

docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${GRAFANA_PORT}:3000" \
    -e "GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}" \
    -e "GF_INSTALL_PLUGINS=grafana-timestream-datasource" \
    -v "${PROVISIONING_DIR}:/etc/grafana/provisioning" \
    -v "${GRAFANA_DIR}/dashboards:/var/lib/grafana/dashboards" \
    grafana/grafana:latest

# Wait for Grafana to start
info "Waiting for Grafana to start..."
for i in $(seq 1 30); do
    if curl -s "http://localhost:${GRAFANA_PORT}/api/health" | grep -q "ok" 2>/dev/null; then
        break
    fi
    sleep 2
done

if curl -s "http://localhost:${GRAFANA_PORT}/api/health" | grep -q "ok" 2>/dev/null; then
    pass "Grafana is running"
else
    fail "Grafana did not start within 60 seconds"
    info "Check logs: docker logs $CONTAINER_NAME"
    exit 1
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Grafana is ready!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  URL:      http://localhost:${GRAFANA_PORT}"
echo "  Username: admin"
echo "  Password: ${GRAFANA_PASSWORD}"
echo ""
echo "  The Timestream datasource and ColdTrack dashboard"
echo "  are pre-configured and ready to use."
echo ""
echo "  To view the dashboard:"
echo "    1. Open http://localhost:${GRAFANA_PORT}"
echo "    2. Log in with admin / ${GRAFANA_PASSWORD}"
echo "    3. Go to Dashboards → ColdTrack → ColdTrack Overview"
echo ""
echo "  To generate live data:"
echo "    python3 scripts/simulate-device.py"
echo ""
echo "  To stop Grafana:"
echo "    docker stop ${CONTAINER_NAME}"
echo ""
echo "  To restart Grafana:"
echo "    docker start ${CONTAINER_NAME}"
echo ""
