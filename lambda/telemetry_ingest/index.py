"""
ColdTrack Telemetry Ingest Lambda
=================================

Triggered by IoT Rule on `coldtrack/sensors/+/data`. The ESP32 firmware
calculates the risk score at the edge — we trust those values and do
NOT recompute risk in the cloud. Per message the Lambda:

  1. Resolves the RFID uid → batch → active shipment
     (via GSI on coldtrack-batches).
  2. Writes the time-series point to InfluxDB, tagged by device_id,
     shipment_id, and batch_id.
  3. Upserts the shipment's current state in DynamoDB
     (currentTemp, riskLevel, riskScore, currentLocation when GPS is
      fixed, lastUpdated, plus the four risk-breakdown sub-scores so
      the dashboard can explain *why* the status is what it is).
  4. If `alert` flag is true AND the shipment doesn't already have an
     active alert, creates one and links it.

Expected payload (firmware schema_version 1.0)
---------------------------------------------
{
  "schema_version": "1.0",
  "device_id": "ESP32_TMP102_GPS_RFID_01",
  "shipment_active": true,
  "rfid_uid": "46:FB:B2:06",
  "threshold_profile": "RSV_2_8C",
  "safe_temp_min_c": 2,
  "safe_temp_max_c": 8,
  "temperature_c": 23.75,             # may be null when probe NaN
  "excursion_seconds": 60,
  "latitude": 51.4681,                # null when no GPS fix
  "longitude": -0.0933,               # null when no GPS fix
  "gps_fix": false,
  "satellites": 0,
  "hdop": 99.9,
  "vibration_count_10s": 0,
  "temperature_risk": 70,
  "duration_risk": 9,
  "vibration_risk": 0,
  "gps_risk": 5,
  "risk_score": 84,                   # 0-100 (we normalise to 0-1)
  "status": "CRITICAL",               # SAFE | WARNING | CRITICAL
  "alert": true,
  "rssi": -56,
  "timestamp": 1777216380             # Unix seconds
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
import urllib.parse
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

# Map firmware status strings to the dashboard's RiskLevel.
# The firmware emits SAFE / WARNING / CRITICAL only. We map WARNING+alert
# straight through; CRITICAL becomes our existing "critical" level.
_STATUS_TO_RISK_LEVEL = {
    "SAFE": "safe",
    "WARNING": "warning",
    "CRITICAL": "critical",
}


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
def lambda_handler(event, _context):
    log.info("event=%s", json.dumps(event)[:600])

    device_id = event.get("device_id") or event.get("topicDeviceId")
    uid = event.get("rfid_uid") or event.get("uid")  # back-compat with older firmware
    temp = _to_float(event.get("temperature_c"))
    if temp is None:
        temp = _to_float(event.get("temperature"))  # back-compat
    unix_ts = int(event.get("timestamp") or time.time())
    ts_iso = datetime.fromtimestamp(unix_ts, tz=timezone.utc).isoformat()
    lat = _to_float(event.get("latitude"))
    lng = _to_float(event.get("longitude"))
    has_gps = bool(event.get("gps_fix")) and lat is not None and lng is not None

    if device_id is None:
        log.error("Bad payload (missing device_id): %s", event)
        return {"status": "bad_payload"}

    # temp is allowed to be None — TMP102 may NaN if probe is disconnected;
    # the device still emits a meaningful risk score and status from the
    # other dimensions (vibration, GPS, duration). Don't drop the message.
    temp_present = temp is not None
    if not temp_present:
        log.info("temperature_c is null; proceeding with non-temp risk dims")

    # ---- 1. Resolve RFID → batch → shipment ---------------------------
    batch_id = None
    shipment_id = None

    if uid:
        batch = _find_batch_by_rfid(uid)
        if batch:
            batch_id = batch.get("batchId")
            shipment_id = batch.get("currentShipmentId")

    # ---- 2. Always write telemetry to InfluxDB ------------------------
    if INFLUX_URL and INFLUX_TOKEN:
        _write_influx_point(
            device_id=device_id,
            shipment_id=shipment_id,
            batch_id=batch_id,
            temperature=temp,  # None is OK — _write_influx_point will skip the field
            risk_score=_to_float(event.get("risk_score")),
            lat=lat if has_gps else None,
            lng=lng if has_gps else None,
            rssi=_to_float(event.get("rssi")),
            vibration=_to_float(event.get("vibration_count_10s")),
            unix_seconds=unix_ts,
        )

    if not shipment_id:
        log.info("uid=%s not bound to a shipment; telemetry logged only", uid)
        return {"status": "logged_without_shipment", "uid": uid}

    # ---- 3. Trust the edge-computed risk ------------------------------
    raw_status = (event.get("status") or "SAFE").upper()
    risk_level = _STATUS_TO_RISK_LEVEL.get(raw_status, "safe")
    raw_risk_score = _to_float(event.get("risk_score"), 0.0) or 0.0
    risk_score_normalised = max(0.0, min(1.0, raw_risk_score / 100.0))
    excursion_seconds = int(_to_float(event.get("excursion_seconds"), 0) or 0)
    # remainingSafeMinutes is not provided by the device; derive a coarse
    # fallback from inverse risk so the existing UI's "safe for X min"
    # countdown still has something to display.
    remaining_min = max(1, int(round((1 - risk_score_normalised) * 60)))

    update_expr = (
        "SET riskLevel = :rl, riskScore = :rs, "
        "remainingSafeMinutes = :rm, secondsOutsideRange = :so, "
        "lastUpdated = :u, deviceId = :d, "
        "temperatureRisk = :tr, durationRisk = :dr, "
        "vibrationRisk = :vr, gpsRisk = :gr, "
        "thresholdProfile = :tp, gpsFix = :gf, "
        "vibrationCount10s = :vc, satellites = :sat, "
        "temperatureSensorOk = :tok"
    )
    attr_vals = {
        ":rl": risk_level,
        ":rs": Decimal(str(round(risk_score_normalised, 2))),
        ":rm": Decimal(str(remaining_min)),
        ":so": Decimal(str(excursion_seconds)),
        ":u": ts_iso,
        ":d": device_id,
        ":tr": Decimal(str(int(_to_float(event.get("temperature_risk"), 0) or 0))),
        ":dr": Decimal(str(int(_to_float(event.get("duration_risk"), 0) or 0))),
        ":vr": Decimal(str(int(_to_float(event.get("vibration_risk"), 0) or 0))),
        ":gr": Decimal(str(int(_to_float(event.get("gps_risk"), 0) or 0))),
        ":tp": event.get("threshold_profile") or "",
        ":gf": bool(event.get("gps_fix")),
        ":vc": Decimal(str(int(_to_float(event.get("vibration_count_10s"), 0) or 0))),
        ":sat": Decimal(str(int(_to_float(event.get("satellites"), 0) or 0))),
        ":tok": temp_present,
    }
    if temp_present:
        update_expr += ", currentTemp = :t"
        attr_vals[":t"] = Decimal(str(round(temp, 2)))
    if has_gps:
        update_expr += ", currentLocation = :loc"
        attr_vals[":loc"] = {"lat": Decimal(str(lat)), "lng": Decimal(str(lng))}

    _shipments.update_item(
        Key={"id": shipment_id},
        UpdateExpression=update_expr,
        ExpressionAttributeValues=attr_vals,
    )

    # ---- 4. Create alert when device flags one (idempotent) ----------
    if bool(event.get("alert")) and risk_level != "safe":
        _maybe_create_alert(
            shipment_id=shipment_id,
            batch_id=batch_id,
            # When temp probe is dead the alert is driven by other dims;
            # store sentinel -1 so downstream UI can render "—" cleanly.
            temperature=temp if temp_present else -1.0,
            risk_level=risk_level,
            risk_score=risk_score_normalised,
            remaining_min=remaining_min,
            ts_iso=ts_iso,
        )

    return {
        "status": "ok",
        "shipment": shipment_id,
        "risk": risk_level,
        "score": raw_risk_score,
    }


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

    # InfluxDB requires at least one field. Build a dict with whatever's
    # available; skip temperature when the probe is unreadable.
    fields = {}
    for name, src_key in (
        ("temperature", "temperature"),
        ("lat", "lat"),
        ("lng", "lng"),
        ("rssi", "rssi"),
        ("vibration", "vibration"),
        ("risk_score", "risk_score"),
    ):
        v = kw.get(src_key)
        if v is not None:
            fields[name] = v
    if not fields:
        log.info("Skipping Influx write — no fields populated")
        return

    ns = int(kw["unix_seconds"]) * 1_000_000_000
    tag_str = ",".join(f"{k}={_influx_escape(v)}" for k, v in tags.items())
    field_str = ",".join(f"{k}={v}" for k, v in fields.items())
    line = f"sensor,{tag_str} {field_str} {ns}"

    # Org and bucket can contain spaces ("UCL IoT Team") — must be URL-encoded
    # or urllib refuses to send the request.
    qs = urllib.parse.urlencode({
        "org": INFLUX_ORG,
        "bucket": INFLUX_BUCKET,
        "precision": "ns",
    })
    url = f"{INFLUX_URL}/api/v2/write?{qs}"
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
