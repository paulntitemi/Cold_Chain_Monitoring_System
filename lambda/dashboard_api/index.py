"""
ColdTrack Dashboard + Rider API
===============================

Single Lambda behind an API Gateway HTTP API. Serves every endpoint the
/web dashboard and /mobile/coldtrack-pwa call. Backed entirely by
DynamoDB; the ingest Lambda (telemetry_ingest) is what actually
populates the shipments/alerts state via IoT Core.

Routes
------
  # Fleet + shipments (dashboard)
  GET    /fleet/active
  GET    /shipments/{id}
  GET    /batches
  GET    /batches/{id}
  POST   /batches
  PATCH  /batches/{id}
  GET    /alerts
  GET    /alerts/active
  PATCH  /alerts/{id}
  POST   /incidents
  GET    /riders
  GET    /storage-centres

  # Rider-specific (PWA)
  GET    /riders/me
  GET    /riders/me/shipment
  GET    /riders/me/alerts
  GET    /riders/me/assignments
  POST   /shipments/{id}/start
  POST   /shipments/{id}/ping
  POST   /handoffs

Rider identity
--------------
Phase 1 (current): a single guest identity. The rider ID is read from the
`x-rider-id` request header; default is `R-006` (Jake Fletcher), so the
PWA works out-of-the-box with Cognito Identity Pool guest access.

Phase 2: swap to Cognito User Pool; read the sub claim from the JWT in
requestContext.authorizer.jwt.claims.sub and map that to the rider row.

Env
---
  SHIPMENTS_TABLE       default: coldtrack-shipments
  ALERTS_TABLE          default: coldtrack-alerts
  BATCHES_TABLE         default: coldtrack-batches
  RIDERS_TABLE          default: coldtrack-riders
  HANDOFFS_TABLE        default: coldtrack-handoffs
  STORAGE_CENTRES_TABLE default: coldtrack-storage-centres  (optional)
  DEFAULT_RIDER_ID      default: R-006
"""

import json
import logging
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Attr, Key

log = logging.getLogger()
log.setLevel(logging.INFO)

_ddb = boto3.resource("dynamodb")
_shipments = _ddb.Table(os.environ.get("SHIPMENTS_TABLE", "coldtrack-shipments"))
_alerts = _ddb.Table(os.environ.get("ALERTS_TABLE", "coldtrack-alerts"))
_batches = _ddb.Table(os.environ.get("BATCHES_TABLE", "coldtrack-batches"))
_riders = _ddb.Table(os.environ.get("RIDERS_TABLE", "coldtrack-riders"))
_handoffs = _ddb.Table(os.environ.get("HANDOFFS_TABLE", "coldtrack-handoffs"))
_centres_table_name = os.environ.get("STORAGE_CENTRES_TABLE", "coldtrack-storage-centres")
_DEFAULT_RIDER = os.environ.get("DEFAULT_RIDER_ID", "R-006")

_CORS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "*",
    "Content-Type": "application/json",
}


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
def lambda_handler(event, _context):
    try:
        method = event.get("requestContext", {}).get("http", {}).get("method", "GET").upper()
        path = event.get("rawPath") or event.get("path") or "/"
        query = event.get("queryStringParameters") or {}
        path_params = event.get("pathParameters") or {}
        headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
        body = _parse_body(event)

        if method == "OPTIONS":
            return _response(204, None)

        log.info("%s %s", method, path)

        route = (method, _route_pattern(path))

        # Fleet / shipments ----------------------------------------------------
        if route == ("GET", "/fleet/active"):
            return _get_active_fleet()
        if route == ("GET", "/shipments/{id}"):
            return _get_shipment(path_params["id"])
        if route == ("POST", "/shipments/{id}/start"):
            return _start_shipment(path_params["id"], body)
        if route == ("POST", "/shipments/{id}/ping"):
            return _ping_shipment(path_params["id"], body)

        # Batches -------------------------------------------------------------
        if route == ("GET", "/batches"):
            return _list_batches()
        if route == ("GET", "/batches/{id}"):
            return _get_batch(path_params["id"])
        if route == ("POST", "/batches"):
            return _create_batch(body)
        if route == ("PATCH", "/batches/{id}"):
            return _patch_batch(path_params["id"], body)

        # Alerts --------------------------------------------------------------
        if route == ("GET", "/alerts"):
            return _list_alerts(query)
        if route == ("GET", "/alerts/active"):
            return _list_active_alerts()
        if route == ("PATCH", "/alerts/{id}"):
            return _patch_alert(path_params["id"], body)

        # Incidents -----------------------------------------------------------
        if route == ("POST", "/incidents"):
            return _log_incident(body)

        # Riders + rider-specific ---------------------------------------------
        if route == ("GET", "/riders"):
            return _list_riders()
        if route == ("GET", "/riders/me"):
            return _get_me(headers)
        if route == ("GET", "/riders/me/shipment"):
            return _get_my_shipment(headers)
        if route == ("GET", "/riders/me/alerts"):
            return _get_my_alerts(headers)
        if route == ("GET", "/riders/me/assignments"):
            return _get_my_assignments(headers)

        # Handoffs ------------------------------------------------------------
        if route == ("POST", "/handoffs"):
            return _create_handoff(body)

        # Storage centres -----------------------------------------------------
        if route == ("GET", "/storage-centres"):
            return _list_centres()

        return _response(404, {"error": f"No route: {method} {path}"})

    except Exception as e:
        log.exception("Unhandled")
        return _response(500, {"error": str(e)})


# ---------------------------------------------------------------------------
# Fleet / shipments
# ---------------------------------------------------------------------------
def _get_active_fleet():
    # Scan with filter — volume is small (hundreds of rows max in this domain).
    res = _shipments.scan(FilterExpression=Attr("status").eq("active"))
    items = [_native(i) for i in res.get("Items", [])]
    return _response(200, items)


def _get_shipment(shipment_id):
    item = _shipments.get_item(Key={"id": shipment_id}).get("Item")
    if not item:
        return _response(404, {"error": f"Shipment {shipment_id} not found"})
    return _response(200, _native(item))


def _start_shipment(shipment_id, _body):
    now = _utc_now_iso()
    _shipments.update_item(
        Key={"id": shipment_id},
        UpdateExpression="SET #s = :a, startTime = :t, lastUpdated = :t",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":a": "active", ":t": now},
    )
    return _get_shipment(shipment_id)


def _ping_shipment(shipment_id, body):
    lat = _float(body.get("lat"))
    lng = _float(body.get("lng"))
    if lat is None or lng is None:
        return _response(400, {"error": "lat + lng required"})
    now = _utc_now_iso()
    _shipments.update_item(
        Key={"id": shipment_id},
        UpdateExpression="SET currentLocation = :l, lastUpdated = :t",
        ExpressionAttributeValues={
            ":l": {"lat": Decimal(str(lat)), "lng": Decimal(str(lng))},
            ":t": now,
        },
    )
    return _response(204, None)


# ---------------------------------------------------------------------------
# Batches
# ---------------------------------------------------------------------------
def _list_batches():
    res = _batches.scan()
    return _response(200, [_native(i) for i in res.get("Items", [])])


def _get_batch(batch_id):
    item = _batches.get_item(Key={"batchId": batch_id}).get("Item")
    if not item:
        return _response(404, {"error": f"Batch {batch_id} not found"})
    return _response(200, _native(item))


def _create_batch(body):
    if not body.get("batchId"):
        body["batchId"] = f"BATCH-{uuid.uuid4().hex[:10].upper()}"
    _batches.put_item(Item=_decimalise(body))
    return _response(201, _native(body))


def _patch_batch(batch_id, body):
    if not body:
        return _get_batch(batch_id)
    update_expr, expr_names, expr_vals = _build_update_expr(body)
    _batches.update_item(
        Key={"batchId": batch_id},
        UpdateExpression=update_expr,
        ExpressionAttributeNames=expr_names,
        ExpressionAttributeValues=expr_vals,
    )
    return _get_batch(batch_id)


# ---------------------------------------------------------------------------
# Alerts
# ---------------------------------------------------------------------------
def _list_alerts(_query):
    res = _alerts.scan()
    return _response(200, [_native(i) for i in res.get("Items", [])])


def _list_active_alerts():
    res = _alerts.scan(FilterExpression=Attr("status").eq("active"))
    return _response(200, [_native(i) for i in res.get("Items", [])])


def _patch_alert(alert_id, body):
    if not body:
        return _response(400, {"error": "empty body"})
    update_expr, expr_names, expr_vals = _build_update_expr(body)
    _alerts.update_item(
        Key={"id": alert_id},
        UpdateExpression=update_expr,
        ExpressionAttributeNames=expr_names,
        ExpressionAttributeValues=expr_vals,
    )
    item = _alerts.get_item(Key={"id": alert_id}).get("Item", {})
    return _response(200, _native(item))


# ---------------------------------------------------------------------------
# Incidents (appended to shipment.incidentLog)
# ---------------------------------------------------------------------------
def _log_incident(body):
    shipment_id = body.get("shipmentId")
    if not shipment_id:
        return _response(400, {"error": "shipmentId required"})
    entry = {
        "id": f"INC-{uuid.uuid4().hex[:8].upper()}",
        "timestamp": _utc_now_iso(),
        "eventType": body.get("eventType", "operatorNote"),
        "detail": body.get("detail", ""),
    }
    if body.get("tempAtEvent") is not None:
        entry["tempAtEvent"] = Decimal(str(body["tempAtEvent"]))
    if body.get("operatorName"):
        entry["operatorName"] = body["operatorName"]

    _shipments.update_item(
        Key={"id": shipment_id},
        UpdateExpression="SET incidentLog = list_append(if_not_exists(incidentLog, :empty), :e)",
        ExpressionAttributeValues={":empty": [], ":e": [entry]},
    )
    return _response(201, _native(entry))


# ---------------------------------------------------------------------------
# Riders
# ---------------------------------------------------------------------------
def _list_riders():
    res = _riders.scan()
    return _response(200, [_native(i) for i in res.get("Items", [])])


def _get_me(headers):
    rider_id = _rider_id(headers)
    r = _riders.get_item(Key={"id": rider_id}).get("Item")
    if not r:
        return _response(404, {"error": f"Rider {rider_id} not found"})
    return _response(200, _native(r))


def _get_my_shipment(headers):
    rider_id = _rider_id(headers)
    res = _shipments.scan(
        FilterExpression=Attr("riderId").eq(rider_id) & Attr("status").eq("active")
    )
    items = res.get("Items", [])
    if not items:
        return _response(200, None)
    return _response(200, _native(items[0]))


def _get_my_alerts(headers):
    rider_id = _rider_id(headers)
    # Find the rider's active shipment first, then alerts pointing at it.
    ship_res = _shipments.scan(
        FilterExpression=Attr("riderId").eq(rider_id) & Attr("status").eq("active")
    )
    ships = ship_res.get("Items", [])
    if not ships:
        return _response(200, [])
    shipment_id = ships[0]["id"]
    alert_res = _alerts.scan(
        FilterExpression=Attr("shipmentId").eq(shipment_id) & Attr("status").eq("active")
    )
    return _response(200, [_native(i) for i in alert_res.get("Items", [])])


def _get_my_assignments(headers):
    rider_id = _rider_id(headers)
    res = _shipments.scan(FilterExpression=Attr("riderId").eq(rider_id))
    out = []
    for s in res.get("Items", []):
        out.append({
            "shipmentId": s["id"],
            "dispatchAt": s.get("startTime", _utc_now_iso()),
            "origin": s.get("origin", ""),
            "destination": s.get("destination", ""),
            "destinationLocation": s.get("destinationLocation", {}),
            "batches": [
                {
                    "batchId": bid,
                    "vaccineType": "",
                    "doseCount": 0,
                    "minSafeTemp": 2.0,
                    "maxSafeTemp": 8.0,
                    "vvmStatus": "stage1",
                }
                for bid in s.get("batchIds", [])
            ],
        })
    return _response(200, [_native(x) for x in out])


# ---------------------------------------------------------------------------
# Handoffs
# ---------------------------------------------------------------------------
def _create_handoff(body):
    shipment_id = body.get("shipmentId")
    if not shipment_id:
        return _response(400, {"error": "shipmentId required"})
    handoff_id = f"HO-{uuid.uuid4().hex[:10].upper()}"
    body["id"] = handoff_id
    if "clientTimestamp" not in body:
        body["clientTimestamp"] = _utc_now_iso()
    _handoffs.put_item(Item=_decimalise(body))
    # Mark shipment completed
    _shipments.update_item(
        Key={"id": shipment_id},
        UpdateExpression="SET #s = :c, lastUpdated = :t",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":c": "completed", ":t": _utc_now_iso()},
    )
    return _response(201, _native(body))


# ---------------------------------------------------------------------------
# Storage centres (optional table — returns [] if table doesn't exist)
# ---------------------------------------------------------------------------
def _list_centres():
    try:
        table = _ddb.Table(_centres_table_name)
        res = table.scan()
        return _response(200, [_native(i) for i in res.get("Items", [])])
    except Exception:
        return _response(200, [])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _rider_id(headers):
    return headers.get("x-rider-id") or _DEFAULT_RIDER


def _route_pattern(path):
    """Normalise path to a template with placeholders matching HTTP API v2
    path-parameter syntax, so we can match routes regardless of which id
    is in the URL."""
    # We let API Gateway extract path parameters into `pathParameters`;
    # just replace each dynamic segment with {id}.
    parts = path.strip("/").split("/")
    if not parts or parts == [""]:
        return "/"
    out = []
    # Heuristic: segments that look like resource names stay; anything
    # that looks like an id gets replaced. We instead use API Gateway's
    # pathParameters directly — this function just builds the canonical
    # template to match against.
    known = {"fleet", "active", "shipments", "batches", "alerts",
             "incidents", "riders", "me", "assignments", "shipment",
             "handoffs", "start", "ping", "storage-centres"}
    for p in parts:
        out.append(p if p in known else "{id}")
    return "/" + "/".join(out)


def _build_update_expr(body):
    # Build "SET #k0 = :v0, #k1 = :v1 …" + name/value maps. Skip empty strings.
    update_fragments = []
    names = {}
    values = {}
    for i, (k, v) in enumerate(body.items()):
        nk = f"#k{i}"
        vk = f":v{i}"
        names[nk] = k
        values[vk] = _decimalise(v)
        update_fragments.append(f"{nk} = {vk}")
    return "SET " + ", ".join(update_fragments), names, values


def _decimalise(v):
    """Recursively convert JSON numbers to Decimal for DynamoDB."""
    if isinstance(v, float):
        return Decimal(str(v))
    if isinstance(v, list):
        return [_decimalise(x) for x in v]
    if isinstance(v, dict):
        return {k: _decimalise(x) for k, x in v.items()}
    return v


def _native(v):
    """Recursively convert Decimal back to int/float for JSON output."""
    if isinstance(v, Decimal):
        f = float(v)
        return int(f) if f.is_integer() else f
    if isinstance(v, list):
        return [_native(x) for x in v]
    if isinstance(v, dict):
        return {k: _native(x) for k, x in v.items()}
    return v


def _parse_body(event):
    raw = event.get("body")
    if not raw:
        return {}
    if event.get("isBase64Encoded"):
        import base64
        raw = base64.b64decode(raw).decode("utf-8")
    try:
        return json.loads(raw)
    except (TypeError, json.JSONDecodeError):
        return {}


def _response(status, body):
    return {
        "statusCode": status,
        "headers": _CORS,
        "body": "" if body is None else json.dumps(body, default=str),
    }


def _float(v):
    try:
        return float(v) if v is not None else None
    except (TypeError, ValueError):
        return None


def _utc_now_iso():
    return datetime.now(timezone.utc).isoformat()
