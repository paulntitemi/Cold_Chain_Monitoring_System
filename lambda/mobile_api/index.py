"""
ColdTrack Mobile API Lambda
===========================

Single HTTP-API handler behind three API Gateway routes:

    GET  /devices/{deviceId}/readings?limit=N       → list most recent N readings
    GET  /devices/{deviceId}/readings/latest        → single most recent reading
    POST /incidents                                 → persist a rider incident log

Reads from DynamoDB table `coldtrack-readings` populated by the IoT Rule
`coldtrack_telemetry_to_dynamodb`. Writes incidents to CloudWatch (a
dedicated table can be added later).

Environment variables
---------------------
    READINGS_TABLE   DynamoDB table name (default: coldtrack-readings)
"""

import json
import logging
import os
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_TABLE_NAME = os.environ.get("READINGS_TABLE", "coldtrack-readings")
_dynamodb = boto3.resource("dynamodb")
_table = _dynamodb.Table(_TABLE_NAME)


# ---------------------------------------------------------------------------
# Lambda entry point
# ---------------------------------------------------------------------------
def lambda_handler(event, context):
    route_key = event.get("routeKey") or ""
    path = event.get("rawPath") or event.get("path") or ""
    method = (event.get("requestContext", {}).get("http", {}).get("method")
              or event.get("httpMethod") or "GET").upper()

    logger.info("Request %s %s (routeKey=%s)", method, path, route_key)

    try:
        if method == "GET" and path.endswith("/readings/latest"):
            return _get_latest_reading(event)
        if method == "GET" and "/readings" in path:
            return _list_readings(event)
        if method == "POST" and path.endswith("/incidents"):
            return _log_incident(event)
        return _response(404, {"error": f"Unmatched route: {method} {path}"})
    except Exception as exc:
        logger.exception("Unhandled error")
        return _response(500, {"error": str(exc)})


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------
def _list_readings(event):
    device_id = _path_param(event, "deviceId")
    if not device_id:
        return _response(400, {"error": "deviceId required"})

    limit = _int_query(event, "limit", default=20, max_value=200)

    result = _table.query(
        KeyConditionExpression=Key("deviceId").eq(device_id),
        ScanIndexForward=False,  # newest first
        Limit=limit,
    )
    readings = [_decimal_to_native(item) for item in result.get("Items", [])]

    return _response(200, {
        "deviceId": device_id,
        "readings": readings,
        "latestReading": readings[0] if readings else None,
    })


def _get_latest_reading(event):
    device_id = _path_param(event, "deviceId")
    if not device_id:
        return _response(400, {"error": "deviceId required"})

    result = _table.query(
        KeyConditionExpression=Key("deviceId").eq(device_id),
        ScanIndexForward=False,
        Limit=1,
    )
    items = result.get("Items", [])
    if not items:
        return _response(200, {
            "deviceId": device_id,
            "readings": [],
            "latestReading": None,
        })

    latest = _decimal_to_native(items[0])
    return _response(200, {
        "deviceId": device_id,
        "latestReading": latest,
        "readings": [latest],
    })


def _log_incident(event):
    body = _parse_body(event)
    # Minimal validation — the mobile client already shapes this well.
    for required in ("deviceId", "shipmentId", "eventType"):
        if not body.get(required):
            return _response(400, {"error": f"Missing field: {required}"})

    logger.info("Incident logged: %s", json.dumps(body))
    return _response(201, {"status": "logged"})


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _response(status, body):
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body, default=str),
    }


def _path_param(event, name):
    return (event.get("pathParameters") or {}).get(name)


def _int_query(event, name, default, max_value):
    raw = (event.get("queryStringParameters") or {}).get(name)
    try:
        n = int(raw) if raw is not None else default
    except (ValueError, TypeError):
        n = default
    return max(1, min(n, max_value))


def _parse_body(event):
    raw = event.get("body")
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def _decimal_to_native(obj):
    """DynamoDB returns numbers as Decimal — JSON can't serialise them."""
    if isinstance(obj, list):
        return [_decimal_to_native(i) for i in obj]
    if isinstance(obj, dict):
        return {k: _decimal_to_native(v) for k, v in obj.items()}
    if isinstance(obj, Decimal):
        f = float(obj)
        return int(f) if f.is_integer() else f
    return obj
