"""
ColdTrack Telemetry Ingest Lambda
=================================

Triggered by IoT Rule on `coldtrack/sensors/+/data`. Per message:

  1. Resolve the RFID uid → batch → active shipment
     (via GSI on coldtrack-batches).
  2. Write the time-series point to InfluxDB, tagged by device_id,
     shipment_id, and batch_id.
  3. Upsert the shipment's current state in DynamoDB
     (currentTemp, riskLevel, currentLocation when GPS is fixed,
      lastUpdated).
  4. If temp breaches safe range AND no active alert exists for the
     shipment, create an alert row and link it.

Expected payload
----------------
{
  "device_id": "ESP32_TMP102_GPS_RFID_01",
  "uid": "08:1A:4F:44",              # RFID tag of the vial box
  "temperature": 23.4375,             # Celsius
  "latitude": 51.4681,                # or null
  "longitude": -0.0933,               # or null
  "gps_fix": false,
  "satellites": 0,
  "hdop": 99.9,
  "vibration_count_10s": 0,
  "rssi": -58,
  "timestamp": 1777045939             # Unix seconds
}

Env
---
  INFLUX_URL, INFLUX_TOKEN, INFLUX_ORG, INFLUX_BUCKET
  SHIPMENTS_TABLE         default: coldtrack-shipments
  ALERTS_TABLE            default: coldtrack-alerts
  BATCHES_TABLE           default: coldtrack-batches
  BATCHES_RFID_INDEX      default: rfidUid-index
"""

import json
import logging
import os
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key

log = logging.getLogger()
log.setLevel(logging.INFO)

INFLUX_URL = os.environ.get("INFLUX_URL", "").rstrip("/")
INFLUX_TOKEN = os.environ.get("INFLUX_TOKEN", "")
INFLUX_ORG = os.environ.get("INFLUX_ORG", "coldtrack")
INFLUX_BUCKET = os.environ.get("INFLUX_BUCKET", "sensors")

_ddb = boto3.resource("dynamodb")
_shipments = _ddb.Table(os.environ.get("SHIPMENTS_TABLE", "coldtrack-shipments"))
_alerts = _ddb.Table(os.environ.get("ALERTS_TABLE", "coldtrack-alerts"))
_batches = _ddb.Table(os.environ.get("BATCHES_TABLE", "coldtrack-batches"))
_BATCHES_RFID_INDEX = os.environ.get("BATCHES_RFID_INDEX", "rfidUid-index")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
def lambda_handler(event, _context):
    log.info("event=%s", json.dumps(event)[:500])

    device_id = event.get("device_id") or event.get("topicDeviceId")
    temp = _to_float(event.get("temperature"))
    uid = event.get("uid")
    unix_ts = int(event.get("timestamp") or time.time())
    ts_iso = datetime.fromtimestamp(unix_ts, tz=timezone.utc).isoformat()
    lat = _to_float(event.get("latitude"))
    lng = _to_float(event.get("longitude"))
    has_gps = bool(event.get("gps_fix")) and lat is not None and lng is not None

    if device_id is None or temp is None:
        log.error("Bad payload (missing device_id or temperature): %s", event)
        return {"status": "bad_payload"}

    # ---- 1. Resolve RFID → batch → shipment ---------------------------
    batch_id = None
    shipment_id = None
    min_safe, max_safe = 2.0, 8.0

    if uid:
        batch = _find_batch_by_rfid(uid)
        if batch:
            batch_id = batch.get("batchId")
            shipment_id = batch.get("currentShipmentId")
            min_safe = _to_float(batch.get("minSafeTemp"), 2.0)
            max_safe = _to_float(batch.get("maxSafeTemp"), 8.0)

    # ---- 2. Always write telemetry to InfluxDB ------------------------
    if INFLUX_URL and INFLUX_TOKEN:
        _write_influx_point(
            device_id=device_id,
            shipment_id=shipment_id,
            batch_id=batch_id,
            temperature=temp,
            lat=lat if has_gps else None,
            lng=lng if has_gps else None,
            rssi=_to_float(event.get("rssi")),
            vibration=_to_float(event.get("vibration_count_10s")),
            unix_seconds=unix_ts,
        )

    if not shipment_id:
        log.info("uid=%s not bound to a shipment; telemetry logged only", uid)
        return {"status": "logged_without_shipment", "uid": uid}

    # ---- 3. Compute risk + upsert shipment row ------------------------
    risk_level, risk_score, remaining_min = _compute_risk(temp, min_safe, max_safe)

    update_expr = (
        "SET currentTemp = :t, riskLevel = :r, riskScore = :s, "
        "remainingSafeMinutes = :m, lastUpdated = :u, deviceId = :d"
    )
    attr_vals = {
        ":t": Decimal(str(round(temp, 2))),
        ":r": risk_level,
        ":s": Decimal(str(round(risk_score, 2))),
        ":m": Decimal(str(remaining_min)),
        ":u": ts_iso,
        ":d": device_id,
    }
    if has_gps:
        update_expr += ", currentLocation = :loc"
        attr_vals[":loc"] = {"lat": Decimal(str(lat)), "lng": Decimal(str(lng))}

    _shipments.update_item(
        Key={"id": shipment_id},
        UpdateExpression=update_expr,
        ExpressionAttributeValues=attr_vals,
    )

    # ---- 4. Fire an alert if we've crossed a threshold ----------------
    if risk_level != "safe":
        _maybe_create_alert(
            shipment_id=shipment_id,
            batch_id=batch_id,
            temperature=temp,
            risk_level=risk_level,
            risk_score=risk_score,
            remaining_min=remaining_min,
            ts_iso=ts_iso,
        )

    return {"status": "ok", "shipment": shipment_id, "risk": risk_level}


# ---------------------------------------------------------------------------
# DynamoDB helpers
# ---------------------------------------------------------------------------
def _find_batch_by_rfid(rfid_uid):
    res = _batches.query(
        IndexName=_BATCHES_RFID_INDEX,
        KeyConditionExpression=Key("rfidUid").eq(rfid_uid),
        Limit=1,
    )
    items = res.get("Items") or []
    return items[0] if items else None


def _maybe_create_alert(shipment_id, batch_id, temperature, risk_level,
                        risk_score, remaining_min, ts_iso):
    # Idempotent: if the shipment already points at an active alert, skip.
    ship = _shipments.get_item(Key={"id": shipment_id}).get("Item", {})
    existing_alert_id = ship.get("activeAlertId")
    if existing_alert_id:
        # Could escalate severity here; for now we leave it alone so the
        # dashboard's view of the alert timeline stays stable.
        return

    alert_id = f"ALERT-{datetime.now(timezone.utc).strftime('%Y%m%d')}-{uuid.uuid4().hex[:6].upper()}"
    _alerts.put_item(Item={
        "id": alert_id,
        "shipmentId": shipment_id,
        "batchIds": [batch_id] if batch_id else [],
        "timestamp": ts_iso,
        "riskLevel": risk_level,
        "riskScore": Decimal(str(round(risk_score, 2))),
        "tempAtTrigger": Decimal(str(round(temperature, 2))),
        "remainingSafeMinutes": Decimal(str(remaining_min)),
        "status": "active",
    })
    _shipments.update_item(
        Key={"id": shipment_id},
        UpdateExpression="SET activeAlertId = :a",
        ExpressionAttributeValues={":a": alert_id},
    )
    log.info("Created alert %s for shipment %s (%s @ %.2f°C)",
             alert_id, shipment_id, risk_level, temperature)


# ---------------------------------------------------------------------------
# Risk
# ---------------------------------------------------------------------------
def _compute_risk(temp, min_safe, max_safe):
    excess = max(0.0, temp - max_safe, min_safe - temp)
    if excess <= 0:
        return "safe", min(0.25, max(0.05, (temp - min_safe) / 20)), 80
    if excess < 0.5:
        return "warning", 0.45, max(12, 30 - int(excess * 20))
    if excess < 1.5:
        return "high", 0.74, max(4, 10 - int(excess * 3))
    return "critical", 0.92, max(1, 4 - int(excess))


# ---------------------------------------------------------------------------
# InfluxDB
# ---------------------------------------------------------------------------
def _influx_escape(v):
    return str(v).replace(" ", r"\ ").replace(",", r"\,").replace("=", r"\=")


def _write_influx_point(**kw):
    tags = {"device_id": kw["device_id"]}
    if kw.get("shipment_id"):
        tags["shipment_id"] = kw["shipment_id"]
    if kw.get("batch_id"):
        tags["batch_id"] = kw["batch_id"]

    fields = {"temperature": kw["temperature"]}
    for name in ("lat", "lng", "rssi", "vibration"):
        v = kw.get(name)
        if v is not None:
            fields[name] = v

    ns = int(kw["unix_seconds"]) * 1_000_000_000
    tag_str = ",".join(f"{k}={_influx_escape(v)}" for k, v in tags.items())
    field_str = ",".join(f"{k}={v}" for k, v in fields.items())
    line = f"sensor,{tag_str} {field_str} {ns}"

    url = f"{INFLUX_URL}/api/v2/write?org={INFLUX_ORG}&bucket={INFLUX_BUCKET}&precision=ns"
    req = urllib.request.Request(
        url,
        data=line.encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Token {INFLUX_TOKEN}",
            "Content-Type": "text/plain; charset=utf-8",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=3) as resp:
            if resp.status >= 300:
                log.warning("InfluxDB write returned %s", resp.status)
    except urllib.error.HTTPError as e:
        log.warning("InfluxDB HTTP error: %s %s", e.code, e.read()[:200])
    except Exception as e:
        log.warning("InfluxDB write failed: %s", e)


# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------
def _to_float(v, default=None):
    if v is None:
        return default
    try:
        return float(v)
    except (TypeError, ValueError):
        return default
