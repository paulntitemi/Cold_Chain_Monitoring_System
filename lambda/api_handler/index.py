"""
ColdTrack REST API Handler Lambda

Serves the ColdTrack REST API behind an Amazon API Gateway HTTP API.
Provides endpoints for listing devices, querying telemetry history,
viewing alerts, and sending commands to IoT devices.

Routes:
    GET  /devices                         - List all registered IoT things
    GET  /devices/{deviceId}              - Device details + latest telemetry
    GET  /devices/{deviceId}/telemetry    - Historical telemetry (with filters)
    GET  /alerts                          - Recent temperature violations
    POST /devices/{deviceId}/commands     - Publish command to device via MQTT

Environment variables:
    TIMESTREAM_DB       - Timestream database name
    TIMESTREAM_TABLE    - Timestream table name
    AWS_IOT_ENDPOINT    - AWS IoT Core data endpoint (e.g. xxx-ats.iot.eu-west-1.amazonaws.com)
"""

import json
import logging
import os
from datetime import datetime, timezone
from urllib.parse import unquote

import boto3
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# ---------------------------------------------------------------------------
# AWS clients
# ---------------------------------------------------------------------------
_region = "eu-west-1"
iot_client = boto3.client("iot", region_name=_region)
timestream_query = boto3.client("timestream-query", region_name=_region)

IOT_ENDPOINT = os.environ.get("AWS_IOT_ENDPOINT", "")
iot_data_client = None  # Lazily initialised (needs endpoint URL)

TIMESTREAM_DB = os.environ.get("TIMESTREAM_DB", "ColdTrackDB")
TIMESTREAM_TABLE = os.environ.get("TIMESTREAM_TABLE", "SensorData")

# ---------------------------------------------------------------------------
# CORS headers applied to every response
# ---------------------------------------------------------------------------
CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Content-Type": "application/json",
}


# ===================================================================
# Lambda handler
# ===================================================================

def lambda_handler(event, context):
    """Route an API Gateway v2 (HTTP API) request to the correct handler.

    Parameters
    ----------
    event : dict
        API Gateway v2 payload format.
    context : LambdaContext
        AWS Lambda runtime context.

    Returns
    -------
    dict
        HTTP response with ``statusCode``, ``headers``, and ``body``.
    """
    logger.info("Received API event: %s", json.dumps(event))

    # Handle CORS preflight.
    http_method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    if http_method == "OPTIONS":
        return _response(200, {"message": "CORS preflight OK"})

    raw_path = event.get("rawPath", "/")
    path = unquote(raw_path)
    query_params = event.get("queryStringParameters") or {}

    try:
        # ---------------------------------------------------------------
        # Route matching
        # ---------------------------------------------------------------

        # GET /devices
        if path == "/devices" and http_method == "GET":
            return _handle_list_devices(query_params)

        # GET /alerts
        if path == "/alerts" and http_method == "GET":
            return _handle_list_alerts(query_params)

        # /devices/{deviceId}...
        if path.startswith("/devices/"):
            segments = path.split("/")
            # segments: ['', 'devices', '{deviceId}', ...]
            if len(segments) < 3 or not segments[2]:
                return _response(400, {"error": "Missing deviceId in path"})

            device_id = segments[2]

            # GET /devices/{deviceId}/telemetry
            if len(segments) == 4 and segments[3] == "telemetry" and http_method == "GET":
                return _handle_device_telemetry(device_id, query_params)

            # POST /devices/{deviceId}/commands
            if len(segments) == 4 and segments[3] == "commands" and http_method == "POST":
                body = _parse_body(event)
                return _handle_send_command(device_id, body)

            # GET /devices/{deviceId}
            if len(segments) == 3 and http_method == "GET":
                return _handle_get_device(device_id)

        return _response(404, {"error": f"Route not found: {http_method} {path}"})

    except ClientError as exc:
        logger.error("AWS service error: %s", exc)
        return _response(502, {
            "error": f"AWS service error: {exc.response['Error']['Message']}",
        })
    except Exception as exc:
        logger.error("Unhandled error: %s", exc, exc_info=True)
        return _response(500, {"error": str(exc)})


# ===================================================================
# Route handlers
# ===================================================================

def _handle_list_devices(query_params):
    """List all IoT things registered in the account.

    Supports optional ``nextToken`` and ``maxResults`` query parameters
    for pagination.

    Parameters
    ----------
    query_params : dict

    Returns
    -------
    dict
        API response.
    """
    kwargs = {}
    max_results = query_params.get("maxResults") or query_params.get("limit")
    if max_results:
        kwargs["maxResults"] = min(int(max_results), 250)
    next_token = query_params.get("nextToken")
    if next_token:
        kwargs["nextToken"] = next_token

    response = iot_client.list_things(**kwargs)

    devices = []
    for thing in response.get("things", []):
        devices.append({
            "deviceId": thing.get("thingName"),
            "thingTypeName": thing.get("thingTypeName"),
            "attributes": thing.get("attributes", {}),
            "version": thing.get("version"),
        })

    result = {
        "devices": devices,
        "count": len(devices),
    }
    if "nextToken" in response:
        result["nextToken"] = response["nextToken"]

    return _response(200, result)


def _handle_get_device(device_id):
    """Return device details and its latest telemetry reading.

    Parameters
    ----------
    device_id : str
        IoT thing name.

    Returns
    -------
    dict
        API response.
    """
    # Fetch thing metadata.
    try:
        thing = iot_client.describe_thing(thingName=device_id)
    except iot_client.exceptions.ResourceNotFoundException:
        return _response(404, {"error": f"Device '{device_id}' not found."})

    device_info = {
        "deviceId": thing.get("thingName"),
        "thingTypeName": thing.get("thingTypeName"),
        "attributes": thing.get("attributes", {}),
        "version": thing.get("version"),
        "defaultClientId": thing.get("defaultClientId"),
    }

    # Fetch latest telemetry from Timestream.
    latest_telemetry = _query_latest_telemetry(device_id)

    return _response(200, {
        "device": device_info,
        "latestTelemetry": latest_telemetry,
    })


def _handle_device_telemetry(device_id, query_params):
    """Query historical telemetry for a device.

    Supported query parameters:
        start  - ISO-8601 start time (default: 1 hour ago)
        end    - ISO-8601 end time (default: now)
        limit  - Maximum number of records to return (default: 100)

    Parameters
    ----------
    device_id : str
    query_params : dict

    Returns
    -------
    dict
        API response.
    """
    limit = min(int(query_params.get("limit", "100")), 1000)
    start = query_params.get("start", "")
    end = query_params.get("end", "")

    # Build time filter.
    time_filter = ""
    if start:
        time_filter += f" AND time >= from_iso8601_timestamp('{start}')"
    else:
        time_filter += " AND time >= ago(1h)"

    if end:
        time_filter += f" AND time <= from_iso8601_timestamp('{end}')"

    query = (
        f"SELECT time, measure_name, measure_value::double, measure_value::bigint "
        f"FROM \"{TIMESTREAM_DB}\".\"{TIMESTREAM_TABLE}\" "
        f"WHERE device_id = '{device_id}'"
        f"{time_filter} "
        f"ORDER BY time DESC "
        f"LIMIT {limit}"
    )

    logger.info("Telemetry query: %s", query)

    rows = _execute_timestream_query(query)

    # Pivot rows into per-timestamp records.
    telemetry = _pivot_timestream_rows(rows)

    return _response(200, {
        "deviceId": device_id,
        "telemetry": telemetry,
        "count": len(telemetry),
    })


def _handle_list_alerts(query_params):
    """List recent temperature violations from Timestream.

    Queries temperature readings that fall outside the safe 2-8 C range.

    Supported query parameters:
        hours  - Lookback window in hours (default: 24)
        limit  - Maximum alerts to return (default: 50)

    Parameters
    ----------
    query_params : dict

    Returns
    -------
    dict
        API response.
    """
    hours = int(query_params.get("hours", "24"))
    limit = min(int(query_params.get("limit", "50")), 500)

    query = (
        f"SELECT device_id, time, measure_value::double AS temperature "
        f"FROM \"{TIMESTREAM_DB}\".\"{TIMESTREAM_TABLE}\" "
        f"WHERE measure_name = 'temperature' "
        f"AND time >= ago({hours}h) "
        f"AND (measure_value::double < 2.0 OR measure_value::double > 8.0) "
        f"ORDER BY time DESC "
        f"LIMIT {limit}"
    )

    logger.info("Alerts query: %s", query)

    rows = _execute_timestream_query(query)

    alerts = []
    for row in rows:
        data = row.get("Data", [])
        if len(data) >= 3:
            device_id = data[0].get("ScalarValue", "")
            time_val = data[1].get("ScalarValue", "")
            temp = float(data[2].get("ScalarValue", 0))

            alert_type = "FREEZE" if temp < 0.0 else ("LOW_TEMP" if temp < 2.0 else "HIGH_TEMP")
            severity = "CRITICAL" if temp < 0.0 else "WARNING"

            alerts.append({
                "deviceId": device_id,
                "timestamp": time_val,
                "temperature": temp,
                "alertType": alert_type,
                "severity": severity,
            })

    return _response(200, {
        "alerts": alerts,
        "count": len(alerts),
        "lookbackHours": hours,
    })


def _handle_send_command(device_id, body):
    """Publish a command to a device via MQTT.

    The command is published to the topic
    ``coldtrack/devices/{deviceId}/commands``.

    The request body must contain at least a ``command`` field.

    Parameters
    ----------
    device_id : str
    body : dict

    Returns
    -------
    dict
        API response.
    """
    if not body or "command" not in body:
        return _response(400, {
            "error": "Request body must contain a 'command' field.",
        })

    command = body["command"]
    payload = body.get("payload", {})

    message = {
        "command": command,
        "payload": payload,
        "device_id": device_id,
        "sent_at": datetime.now(timezone.utc).isoformat(),
    }

    topic = f"coldtrack/devices/{device_id}/commands"

    data_client = _get_iot_data_client()
    data_client.publish(
        topic=topic,
        qos=1,
        payload=json.dumps(message).encode("utf-8"),
    )

    logger.info(
        "Published command '%s' to device %s on topic %s",
        command,
        device_id,
        topic,
    )

    return _response(200, {
        "message": f"Command '{command}' sent to device '{device_id}'.",
        "topic": topic,
    })


# ===================================================================
# Timestream query helpers
# ===================================================================

def _query_latest_telemetry(device_id):
    """Fetch the most recent set of measures for a device.

    Parameters
    ----------
    device_id : str

    Returns
    -------
    dict or None
        Dictionary of the latest measure values, or ``None`` if no
        data is available.
    """
    query = (
        f"SELECT measure_name, measure_value::double, measure_value::bigint, time "
        f"FROM \"{TIMESTREAM_DB}\".\"{TIMESTREAM_TABLE}\" "
        f"WHERE device_id = '{device_id}' "
        f"AND time >= ago(1h) "
        f"ORDER BY time DESC "
        f"LIMIT 10"
    )

    rows = _execute_timestream_query(query)
    if not rows:
        return None

    latest = {}
    latest_time = None
    for row in rows:
        data = row.get("Data", [])
        if len(data) >= 4:
            measure = data[0].get("ScalarValue", "")
            double_val = data[1].get("ScalarValue")
            bigint_val = data[2].get("ScalarValue")
            ts = data[3].get("ScalarValue", "")

            value = float(double_val) if double_val else (int(bigint_val) if bigint_val else None)
            latest[measure] = value

            if latest_time is None:
                latest_time = ts

    if latest_time:
        latest["timestamp"] = latest_time

    return latest if latest else None


def _execute_timestream_query(query):
    """Execute a Timestream query and return all result rows.

    Handles pagination transparently.

    Parameters
    ----------
    query : str
        Timestream SQL query string.

    Returns
    -------
    list[dict]
        List of row dicts from the Timestream response.
    """
    all_rows = []
    try:
        paginator = timestream_query.get_paginator("query")
        for page in paginator.paginate(QueryString=query):
            all_rows.extend(page.get("Rows", []))
    except ClientError as exc:
        logger.error("Timestream query failed: %s | Query: %s", exc, query)
        raise

    return all_rows


def _pivot_timestream_rows(rows):
    """Pivot raw Timestream rows into per-timestamp telemetry records.

    Each row from Timestream has a single measure.  This function groups
    measures that share the same timestamp into a single dict.

    Parameters
    ----------
    rows : list[dict]

    Returns
    -------
    list[dict]
        Telemetry records grouped by timestamp.
    """
    time_map = {}
    for row in rows:
        data = row.get("Data", [])
        if len(data) < 4:
            continue

        ts = data[0].get("ScalarValue", "")
        measure = data[1].get("ScalarValue", "")
        double_val = data[2].get("ScalarValue")
        bigint_val = data[3].get("ScalarValue")

        value = float(double_val) if double_val else (int(bigint_val) if bigint_val else None)

        if ts not in time_map:
            time_map[ts] = {"timestamp": ts}
        time_map[ts][measure] = value

    # Return sorted newest first.
    return sorted(time_map.values(), key=lambda r: r.get("timestamp", ""), reverse=True)


# ===================================================================
# Utility helpers
# ===================================================================

def _get_iot_data_client():
    """Lazily initialise and return the IoT Data Plane client.

    The endpoint URL is required to create the client and is read from
    the ``AWS_IOT_ENDPOINT`` environment variable.

    Returns
    -------
    boto3.client
    """
    global iot_data_client
    if iot_data_client is None:
        endpoint = IOT_ENDPOINT
        if not endpoint:
            # Fall back to looking up the endpoint at runtime.
            resp = iot_client.describe_endpoint(endpointType="iot:Data-ATS")
            endpoint = resp["endpointAddress"]
            logger.info("Discovered IoT endpoint: %s", endpoint)

        iot_data_client = boto3.client(
            "iot-data",
            region_name=_region,
            endpoint_url=f"https://{endpoint}",
        )
    return iot_data_client


def _parse_body(event):
    """Extract and parse the JSON body from an API Gateway event.

    Parameters
    ----------
    event : dict

    Returns
    -------
    dict
        Parsed body, or empty dict if missing/invalid.
    """
    raw = event.get("body", "")
    if not raw:
        return {}

    # API Gateway may base64-encode the body.
    if event.get("isBase64Encoded", False):
        import base64
        raw = base64.b64decode(raw).decode("utf-8")

    try:
        return json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        logger.warning("Failed to parse request body as JSON")
        return {}


def _response(status_code, body):
    """Build a standard API Gateway response with CORS headers.

    Parameters
    ----------
    status_code : int
    body : dict

    Returns
    -------
    dict
        API Gateway v2 response format.
    """
    return {
        "statusCode": status_code,
        "headers": CORS_HEADERS,
        "body": json.dumps(body, default=str),
    }
