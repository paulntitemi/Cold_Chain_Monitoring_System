"""
ColdTrack Process Violation Lambda

Processes incoming sensor telemetry from AWS IoT Core, writes data to
AWS Timestream, detects temperature and battery violations, and publishes
alerts to SNS when thresholds are breached.

This is the primary data ingestion Lambda for the ColdTrack RSV vaccine
cold chain monitoring system. It is triggered by an IoT Rule whenever a
device publishes telemetry on the MQTT topic.

Environment variables:
    TIMESTREAM_DB          - Timestream database name
    TIMESTREAM_TABLE       - Timestream table name
    SNS_TOPIC_ARN          - SNS topic ARN for violation alerts
    TEMP_MIN               - Minimum safe temperature in Celsius (default: 2.0)
    TEMP_MAX               - Maximum safe temperature in Celsius (default: 8.0)
    FREEZE_THRESHOLD       - Freeze alert threshold in Celsius (default: 0.0)
    BATTERY_LOW            - Low battery percentage threshold (default: 20)
    BATTERY_CRITICAL       - Critical battery percentage threshold (default: 10)
"""

import json
import logging
import os
import time
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Logging configuration
# ---------------------------------------------------------------------------
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# ---------------------------------------------------------------------------
# AWS clients (initialised outside handler for connection reuse across
# warm Lambda invocations)
# ---------------------------------------------------------------------------
timestream_write = boto3.client("timestream-write", region_name="eu-west-1")
sns_client = boto3.client("sns", region_name="eu-west-1")

# ---------------------------------------------------------------------------
# Configuration from environment
# ---------------------------------------------------------------------------
TIMESTREAM_DB = os.environ.get("TIMESTREAM_DB", "ColdTrackDB")
TIMESTREAM_TABLE = os.environ.get("TIMESTREAM_TABLE", "SensorData")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")

TEMP_MIN = float(os.environ.get("TEMP_MIN", "2.0"))
TEMP_MAX = float(os.environ.get("TEMP_MAX", "8.0"))
FREEZE_THRESHOLD = float(os.environ.get("FREEZE_THRESHOLD", "0.0"))

BATTERY_LOW = float(os.environ.get("BATTERY_LOW", "20"))
BATTERY_CRITICAL = float(os.environ.get("BATTERY_CRITICAL", "10"))


# ===================================================================
# Lambda handler
# ===================================================================

def lambda_handler(event, context):
    """Primary entry point invoked by the AWS IoT Rule action.

    Parameters
    ----------
    event : dict
        Sensor telemetry forwarded by the IoT Rule.  Expected keys:
        ``device_id``, ``temperature``, ``humidity``, ``battery``,
        ``timestamp``, ``latitude``, ``longitude``, ``rssi``.
    context : LambdaContext
        AWS Lambda runtime context.

    Returns
    -------
    dict
        Response with ``statusCode`` and JSON ``body``.
    """
    logger.info("Received event: %s", json.dumps(event))

    try:
        # ------------------------------------------------------------------
        # 1. Extract and validate telemetry fields
        # ------------------------------------------------------------------
        telemetry = _extract_telemetry(event)
        logger.info(
            "Device %s | Temp %.2f C | Humidity %.1f%% | Battery %.1f%%",
            telemetry["device_id"],
            telemetry["temperature"],
            telemetry["humidity"],
            telemetry["battery"],
        )

        # ------------------------------------------------------------------
        # 2. Write record to Timestream
        # ------------------------------------------------------------------
        _write_to_timestream(telemetry)

        # ------------------------------------------------------------------
        # 3. Evaluate violation thresholds
        # ------------------------------------------------------------------
        violations = _check_violations(telemetry)

        # ------------------------------------------------------------------
        # 4. Publish alerts for any detected violations
        # ------------------------------------------------------------------
        if violations:
            logger.warning(
                "Violations detected for device %s: %s",
                telemetry["device_id"],
                json.dumps(violations),
            )
            _publish_alerts(telemetry, violations)

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Telemetry processed successfully",
                "device_id": telemetry["device_id"],
                "violations": violations,
            }),
        }

    except KeyError as exc:
        logger.error("Missing required field in event: %s", exc)
        return {
            "statusCode": 400,
            "body": json.dumps({
                "error": f"Missing required field: {exc}",
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
        logger.error("Unexpected error processing telemetry: %s", exc, exc_info=True)
        return {
            "statusCode": 500,
            "body": json.dumps({
                "error": str(exc),
            }),
        }


# ===================================================================
# Internal helpers
# ===================================================================

def _extract_telemetry(event):
    """Parse and validate telemetry fields from the incoming IoT event.

    Parameters
    ----------
    event : dict
        Raw event payload from IoT Core.

    Returns
    -------
    dict
        Normalised telemetry dictionary with guaranteed numeric types.
    """
    device_id = event.get("device_id")
    if not device_id:
        raise KeyError("device_id")

    return {
        "device_id": str(device_id),
        "temperature": float(event.get("temperature", 0)),
        "humidity": float(event.get("humidity", 0)),
        "battery": float(event.get("battery", 100)),
        "timestamp": int(event.get("timestamp", int(time.time()))),
        "latitude": event.get("latitude"),
        "longitude": event.get("longitude"),
        "rssi": int(event.get("rssi", 0)),
    }


def _write_to_timestream(telemetry):
    """Persist a telemetry record to AWS Timestream.

    The record uses the device_id as a dimension and stores temperature,
    humidity, battery, rssi, and optional GPS coordinates as measures.

    Parameters
    ----------
    telemetry : dict
        Validated telemetry dictionary from ``_extract_telemetry``.
    """
    dimensions = [
        {"Name": "device_id", "Value": telemetry["device_id"]},
    ]

    # Build the common attributes shared by all records in this write.
    common_attributes = {
        "Dimensions": dimensions,
        "Time": str(telemetry["timestamp"]),
        "TimeUnit": "SECONDS",
    }

    records = [
        {
            "MeasureName": "temperature",
            "MeasureValue": str(telemetry["temperature"]),
            "MeasureValueType": "DOUBLE",
        },
        {
            "MeasureName": "humidity",
            "MeasureValue": str(telemetry["humidity"]),
            "MeasureValueType": "DOUBLE",
        },
        {
            "MeasureName": "battery",
            "MeasureValue": str(telemetry["battery"]),
            "MeasureValueType": "DOUBLE",
        },
        {
            "MeasureName": "rssi",
            "MeasureValue": str(telemetry["rssi"]),
            "MeasureValueType": "BIGINT",
        },
    ]

    # Add GPS coordinates when available.
    if telemetry.get("latitude") is not None and telemetry.get("longitude") is not None:
        records.append({
            "MeasureName": "latitude",
            "MeasureValue": str(telemetry["latitude"]),
            "MeasureValueType": "DOUBLE",
        })
        records.append({
            "MeasureName": "longitude",
            "MeasureValue": str(telemetry["longitude"]),
            "MeasureValueType": "DOUBLE",
        })

    try:
        timestream_write.write_records(
            DatabaseName=TIMESTREAM_DB,
            TableName=TIMESTREAM_TABLE,
            CommonAttributes=common_attributes,
            Records=records,
        )
        logger.info(
            "Wrote %d records to Timestream for device %s",
            len(records),
            telemetry["device_id"],
        )
    except timestream_write.exceptions.RejectedRecordsException as exc:
        # Log each rejected record but do not abort -- partial writes are
        # still valuable.
        for rejected in exc.response.get("RejectedRecords", []):
            logger.error(
                "Rejected record index %s: %s",
                rejected.get("RecordIndex"),
                rejected.get("Reason"),
            )
        raise


def _check_violations(telemetry):
    """Evaluate temperature and battery thresholds against telemetry.

    Parameters
    ----------
    telemetry : dict
        Validated telemetry dictionary.

    Returns
    -------
    list[dict]
        A list of violation records.  Each record contains ``type``,
        ``severity``, ``message``, and optionally ``freeze_score``.
    """
    violations = []
    temperature = telemetry["temperature"]
    battery = telemetry["battery"]
    device_id = telemetry["device_id"]

    # ------------------------------------------------------------------
    # Temperature violations
    # ------------------------------------------------------------------
    if temperature < FREEZE_THRESHOLD:
        depth_below_zero = abs(temperature - FREEZE_THRESHOLD)
        freeze_score = _compute_freeze_score(depth_below_zero, severity="CRITICAL")
        violations.append({
            "type": "FREEZE",
            "severity": "CRITICAL",
            "message": (
                f"Freeze alert for device {device_id}! "
                f"Temperature {temperature:.2f} C is below freeze threshold "
                f"{FREEZE_THRESHOLD:.1f} C."
            ),
            "freeze_score": freeze_score,
            "device_id": device_id,
        })
    elif temperature < TEMP_MIN:
        freeze_score = _compute_freeze_score(
            abs(temperature - TEMP_MIN), severity="WARNING"
        )
        violations.append({
            "type": "LOW_TEMP",
            "severity": "WARNING",
            "message": (
                f"Low temperature for device {device_id}: "
                f"{temperature:.2f} C (min {TEMP_MIN:.1f} C)."
            ),
            "freeze_score": freeze_score,
            "device_id": device_id,
        })
    elif temperature > TEMP_MAX:
        violations.append({
            "type": "HIGH_TEMP",
            "severity": "WARNING",
            "message": (
                f"High temperature for device {device_id}: "
                f"{temperature:.2f} C (max {TEMP_MAX:.1f} C)."
            ),
            "device_id": device_id,
        })

    # ------------------------------------------------------------------
    # Battery violations
    # ------------------------------------------------------------------
    if battery < BATTERY_CRITICAL:
        violations.append({
            "type": "BATTERY_CRITICAL",
            "severity": "CRITICAL",
            "message": (
                f"Critical battery on device {device_id}: {battery:.1f}%."
            ),
            "device_id": device_id,
        })
    elif battery < BATTERY_LOW:
        violations.append({
            "type": "BATTERY_LOW",
            "severity": "WARNING",
            "message": (
                f"Low battery on device {device_id}: {battery:.1f}%."
            ),
            "device_id": device_id,
        })

    return violations


def _compute_freeze_score(depth_below_threshold, severity="WARNING"):
    """Compute a numerical freeze risk score.

    The score combines the depth below the threshold with the severity
    level to produce a value in the range [0, 100].  Higher scores
    indicate more dangerous conditions.

    Parameters
    ----------
    depth_below_threshold : float
        How far (in degrees C) the reading is below the threshold.
    severity : str
        ``"WARNING"`` or ``"CRITICAL"``.

    Returns
    -------
    float
        Freeze score between 0.0 and 100.0.
    """
    severity_multiplier = 2.0 if severity == "CRITICAL" else 1.0

    # Each degree below threshold contributes 10 points, scaled by
    # severity and capped at 100.
    raw_score = depth_below_threshold * 10.0 * severity_multiplier
    return round(min(raw_score, 100.0), 2)


def _publish_alerts(telemetry, violations):
    """Publish each violation as an SNS notification.

    Parameters
    ----------
    telemetry : dict
        Validated telemetry dictionary (used for context in the message).
    violations : list[dict]
        Violation records produced by ``_check_violations``.
    """
    if not SNS_TOPIC_ARN:
        logger.warning("SNS_TOPIC_ARN not configured; skipping alert publication.")
        return

    for violation in violations:
        subject = (
            f"[ColdTrack {violation['severity']}] "
            f"{violation['type']} - Device {telemetry['device_id']}"
        )
        # SNS subject max length is 100 characters.
        subject = subject[:100]

        message_body = {
            "default": violation["message"],
            "violation": violation,
            "telemetry": {
                "device_id": telemetry["device_id"],
                "temperature": telemetry["temperature"],
                "humidity": telemetry["humidity"],
                "battery": telemetry["battery"],
                "timestamp": telemetry["timestamp"],
                "latitude": telemetry.get("latitude"),
                "longitude": telemetry.get("longitude"),
            },
            "alert_timestamp": datetime.now(timezone.utc).isoformat(),
        }

        try:
            sns_client.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=subject,
                Message=json.dumps(message_body),
                MessageStructure="string",
            )
            logger.info(
                "Published %s alert to SNS for device %s",
                violation["type"],
                telemetry["device_id"],
            )
        except ClientError as exc:
            logger.error(
                "Failed to publish SNS alert for device %s: %s",
                telemetry["device_id"],
                exc,
            )
