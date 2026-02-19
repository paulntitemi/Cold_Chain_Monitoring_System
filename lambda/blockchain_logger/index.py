"""
ColdTrack Blockchain Audit Logger Lambda

Creates tamper-evident, hash-chained audit log records for every
temperature event processed by the ColdTrack system.  Each record is
linked to its predecessor via a SHA-256 hash, forming an immutable chain
that can be independently verified at any time.

This provides regulators and supply-chain partners with cryptographic
proof that cold chain records have not been altered -- a requirement for
pharmaceutical-grade RSV vaccine logistics.

Supported actions (determined by ``event["action"]``):
    * ``log``    -- (default) Create a new chained audit record.
    * ``verify`` -- Walk the chain for a device and verify integrity.

Environment variables:
    TABLE_NAME   - DynamoDB table name for audit records
    AWS_REGION   - AWS region (default: eu-west-1)
"""

import hashlib
import json
import logging
import os
import time
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# ---------------------------------------------------------------------------
# AWS resources (reused across warm invocations)
# ---------------------------------------------------------------------------
_region = os.environ.get("AWS_REGION", "eu-west-1")
dynamodb = boto3.resource("dynamodb", region_name=_region)
TABLE_NAME = os.environ.get("TABLE_NAME", "ColdTrackAuditLog")
table = dynamodb.Table(TABLE_NAME)

# The genesis hash used for the very first record of each device chain.
GENESIS_HASH = "0" * 64


# ===================================================================
# Lambda handler
# ===================================================================

def lambda_handler(event, context):
    """Route incoming requests to the appropriate action handler.

    Parameters
    ----------
    event : dict
        Must contain ``action`` (``"log"`` or ``"verify"``).  For
        ``"log"`` the event should also carry the telemetry fields
        (``device_id``, ``temperature``, ``timestamp``, etc.).  For
        ``"verify"`` only ``device_id`` is required.
    context : LambdaContext
        AWS Lambda runtime context.

    Returns
    -------
    dict
        Response with ``statusCode`` and JSON ``body``.
    """
    logger.info("Received event: %s", json.dumps(event, default=str))

    action = event.get("action", "log").lower()

    try:
        if action == "log":
            return _handle_log(event)
        elif action == "verify":
            return _handle_verify(event)
        else:
            return {
                "statusCode": 400,
                "body": json.dumps({
                    "error": f"Unknown action: '{action}'. Supported: log, verify.",
                }),
            }
    except ClientError as exc:
        logger.error("AWS service error: %s", exc)
        return {
            "statusCode": 502,
            "body": json.dumps({
                "error": f"AWS service error: {exc.response['Error']['Message']}",
            }),
        }
    except Exception as exc:
        logger.error("Unexpected error: %s", exc, exc_info=True)
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(exc)}),
        }


# ===================================================================
# Action handlers
# ===================================================================

def _handle_log(event):
    """Create a new hash-chained audit record.

    Parameters
    ----------
    event : dict
        Telemetry payload with at least ``device_id`` and
        ``temperature``.

    Returns
    -------
    dict
        Response containing the record hash.
    """
    device_id = event.get("device_id")
    if not device_id:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Missing required field: device_id"}),
        }

    temperature = float(event.get("temperature", 0))
    timestamp = int(event.get("timestamp", int(time.time())))
    latitude = event.get("latitude")
    longitude = event.get("longitude")
    humidity = event.get("humidity")
    battery = event.get("battery")

    # Determine violation info if supplied by the caller.
    violation_flag = event.get("violation", False)
    severity = event.get("severity", "NONE")

    # Retrieve the previous record hash for this device.
    previous_hash = _get_latest_hash(device_id)

    # Build the canonical data block that will be hashed.
    record_data = {
        "device_id": device_id,
        "temperature": temperature,
        "timestamp": timestamp,
        "latitude": latitude,
        "longitude": longitude,
        "violation": violation_flag,
        "severity": severity,
        "previous_hash": previous_hash,
    }

    record_hash = _compute_hash(record_data)

    # Persist to DynamoDB.
    record_id = str(uuid.uuid4())
    item = {
        "device_id": device_id,
        "record_id": record_id,
        "timestamp": timestamp,
        "iso_time": datetime.fromtimestamp(timestamp, tz=timezone.utc).isoformat(),
        "temperature": _to_decimal(temperature),
        "humidity": _to_decimal(humidity) if humidity is not None else None,
        "battery": _to_decimal(battery) if battery is not None else None,
        "latitude": _to_decimal(latitude) if latitude is not None else None,
        "longitude": _to_decimal(longitude) if longitude is not None else None,
        "violation": violation_flag,
        "severity": severity,
        "previous_hash": previous_hash,
        "record_hash": record_hash,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    # Remove None values (DynamoDB does not accept None).
    item = {k: v for k, v in item.items() if v is not None}

    table.put_item(Item=item)

    logger.info(
        "Audit record stored for device %s | hash=%s | prev=%s",
        device_id,
        record_hash[:16] + "...",
        previous_hash[:16] + "...",
    )

    return {
        "statusCode": 201,
        "body": json.dumps({
            "message": "Audit record created",
            "device_id": device_id,
            "record_id": record_id,
            "record_hash": record_hash,
            "previous_hash": previous_hash,
        }),
    }


def _handle_verify(event):
    """Verify the integrity of the hash chain for a device.

    Walks from the newest record to the genesis and checks that each
    record's hash matches the ``previous_hash`` pointer of its
    successor.

    Parameters
    ----------
    event : dict
        Must contain ``device_id``.

    Returns
    -------
    dict
        Verification result with ``valid`` (bool), ``records_checked``
        (int), and ``errors`` (list).
    """
    device_id = event.get("device_id")
    if not device_id:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Missing required field: device_id"}),
        }

    # Fetch all records for the device sorted by timestamp ascending.
    records = _get_all_records(device_id)

    if not records:
        return {
            "statusCode": 200,
            "body": json.dumps({
                "device_id": device_id,
                "valid": True,
                "records_checked": 0,
                "message": "No audit records found for this device.",
            }),
        }

    errors = []
    records_checked = 0

    for idx, record in enumerate(records):
        records_checked += 1

        # Recompute the hash from the stored data fields.
        record_data = {
            "device_id": record["device_id"],
            "temperature": float(record.get("temperature", 0)),
            "timestamp": int(record.get("timestamp", 0)),
            "latitude": _from_decimal(record.get("latitude")),
            "longitude": _from_decimal(record.get("longitude")),
            "violation": record.get("violation", False),
            "severity": record.get("severity", "NONE"),
            "previous_hash": record.get("previous_hash", GENESIS_HASH),
        }
        expected_hash = _compute_hash(record_data)
        stored_hash = record.get("record_hash", "")

        if expected_hash != stored_hash:
            errors.append({
                "record_id": record.get("record_id"),
                "timestamp": record.get("timestamp"),
                "error": "Hash mismatch: record data has been tampered with.",
                "expected": expected_hash,
                "stored": stored_hash,
            })

        # Verify chain linkage (except for the first record).
        if idx > 0:
            prev_record = records[idx - 1]
            if record.get("previous_hash") != prev_record.get("record_hash"):
                errors.append({
                    "record_id": record.get("record_id"),
                    "timestamp": record.get("timestamp"),
                    "error": "Chain link broken: previous_hash does not match preceding record.",
                })

        # The first record should reference the genesis hash.
        if idx == 0 and record.get("previous_hash") != GENESIS_HASH:
            # Not necessarily an error if the chain was started mid-stream,
            # but flag it as a warning.
            errors.append({
                "record_id": record.get("record_id"),
                "timestamp": record.get("timestamp"),
                "error": "First record does not reference genesis hash.",
            })

    is_valid = len(errors) == 0

    logger.info(
        "Chain verification for device %s: valid=%s, checked=%d, errors=%d",
        device_id,
        is_valid,
        records_checked,
        len(errors),
    )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "device_id": device_id,
            "valid": is_valid,
            "records_checked": records_checked,
            "errors": errors,
        }),
    }


# ===================================================================
# Internal helpers
# ===================================================================

def _compute_hash(record_data):
    """Compute a deterministic SHA-256 hash for a record.

    The record data is serialised to a canonical JSON string (sorted
    keys, no whitespace) before hashing.

    Parameters
    ----------
    record_data : dict

    Returns
    -------
    str
        Hex-encoded SHA-256 digest.
    """
    canonical = json.dumps(record_data, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _get_latest_hash(device_id):
    """Retrieve the hash of the most recent audit record for a device.

    Parameters
    ----------
    device_id : str

    Returns
    -------
    str
        The ``record_hash`` of the latest record, or ``GENESIS_HASH``
        if no records exist yet.
    """
    try:
        response = table.query(
            KeyConditionExpression=Key("device_id").eq(device_id),
            ScanIndexForward=False,  # Descending by sort key
            Limit=1,
            ProjectionExpression="record_hash",
        )
        items = response.get("Items", [])
        if items:
            return items[0].get("record_hash", GENESIS_HASH)
    except ClientError as exc:
        logger.error("Error querying latest hash for %s: %s", device_id, exc)

    return GENESIS_HASH


def _get_all_records(device_id):
    """Retrieve all audit records for a device, sorted by timestamp.

    Parameters
    ----------
    device_id : str

    Returns
    -------
    list[dict]
        Records in ascending chronological order.
    """
    records = []
    try:
        response = table.query(
            KeyConditionExpression=Key("device_id").eq(device_id),
            ScanIndexForward=True,  # Ascending
        )
        records.extend(response.get("Items", []))

        # Handle pagination for devices with many records.
        while "LastEvaluatedKey" in response:
            response = table.query(
                KeyConditionExpression=Key("device_id").eq(device_id),
                ScanIndexForward=True,
                ExclusiveStartKey=response["LastEvaluatedKey"],
            )
            records.extend(response.get("Items", []))

    except ClientError as exc:
        logger.error("Error querying records for %s: %s", device_id, exc)

    return records


def _to_decimal(value):
    """Convert a numeric value to ``Decimal`` for DynamoDB storage.

    Parameters
    ----------
    value : int, float, or None

    Returns
    -------
    Decimal or None
    """
    if value is None:
        return None
    return Decimal(str(value))


def _from_decimal(value):
    """Convert a DynamoDB ``Decimal`` back to a Python float.

    Parameters
    ----------
    value : Decimal, int, float, or None

    Returns
    -------
    float or None
    """
    if value is None:
        return None
    return float(value)
