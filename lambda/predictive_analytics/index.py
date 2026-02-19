"""
ColdTrack Predictive Analytics Lambda

Analyses recent telemetry trends for a given device and predicts whether
the temperature will drift out of the safe RSV vaccine storage range
(2-8 C) within a configurable prediction window.

The function queries the last N readings from AWS Timestream, computes a
moving average and a linear rate of change, then extrapolates to
determine if an excursion is likely.  When a predicted excursion is
detected the function publishes a pre-emptive warning to SNS so that
operators can intervene before product loss occurs.

Trigger modes:
    * Scheduled via Amazon EventBridge (CloudWatch Events) -- the event
      must contain a ``device_id`` field (or a ``device_ids`` list).
    * Direct invocation from another Lambda or Step Function.

Environment variables:
    TIMESTREAM_DB               - Timestream database name
    TIMESTREAM_TABLE            - Timestream table name
    SNS_TOPIC_ARN               - SNS topic ARN for predictive warnings
    PREDICTION_WINDOW_MINUTES   - How far ahead to predict (default: 30)
    LOOKBACK_READINGS           - Number of recent readings to analyse (default: 20)
    TEMP_MIN                    - Minimum safe temperature (default: 2.0)
    TEMP_MAX                    - Maximum safe temperature (default: 8.0)
"""

import json
import logging
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# ---------------------------------------------------------------------------
# AWS clients (reused across warm invocations)
# ---------------------------------------------------------------------------
timestream_query = boto3.client("timestream-query", region_name="eu-west-1")
sns_client = boto3.client("sns", region_name="eu-west-1")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
TIMESTREAM_DB = os.environ.get("TIMESTREAM_DB", "ColdTrackDB")
TIMESTREAM_TABLE = os.environ.get("TIMESTREAM_TABLE", "SensorData")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
PREDICTION_WINDOW_MINUTES = int(os.environ.get("PREDICTION_WINDOW_MINUTES", "30"))
LOOKBACK_READINGS = int(os.environ.get("LOOKBACK_READINGS", "20"))
TEMP_MIN = float(os.environ.get("TEMP_MIN", "2.0"))
TEMP_MAX = float(os.environ.get("TEMP_MAX", "8.0"))


# ===================================================================
# Lambda handler
# ===================================================================

def lambda_handler(event, context):
    """Analyse temperature trends and predict excursions.

    Parameters
    ----------
    event : dict
        Must contain either ``device_id`` (str) or ``device_ids`` (list
        of str).  When triggered by EventBridge the event can carry
        these inside a ``detail`` key.
    context : LambdaContext
        AWS Lambda runtime context.

    Returns
    -------
    dict
        Response containing prediction results per device.
    """
    logger.info("Received event: %s", json.dumps(event))

    try:
        device_ids = _resolve_device_ids(event)
        if not device_ids:
            return {
                "statusCode": 400,
                "body": json.dumps({
                    "error": "No device_id or device_ids provided in event.",
                }),
            }

        results = {}
        for device_id in device_ids:
            prediction = _analyse_device(device_id)
            results[device_id] = prediction

            if prediction.get("excursion_predicted"):
                _publish_warning(device_id, prediction)

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Predictive analysis complete",
                "predictions": results,
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
# Internal helpers
# ===================================================================

def _resolve_device_ids(event):
    """Extract one or more device IDs from the event payload.

    Supports both direct invocation (``device_id`` / ``device_ids`` at
    the top level) and EventBridge detail payloads.

    Parameters
    ----------
    event : dict

    Returns
    -------
    list[str]
    """
    # Direct invocation
    if "device_ids" in event:
        return list(event["device_ids"])
    if "device_id" in event:
        return [event["device_id"]]

    # EventBridge wrapper
    detail = event.get("detail", {})
    if "device_ids" in detail:
        return list(detail["device_ids"])
    if "device_id" in detail:
        return [detail["device_id"]]

    return []


def _query_recent_readings(device_id):
    """Fetch the most recent temperature readings from Timestream.

    Parameters
    ----------
    device_id : str

    Returns
    -------
    list[dict]
        Each element has ``time`` (ISO string) and ``temperature``
        (float), ordered from oldest to newest.
    """
    query = (
        f"SELECT time, measure_value::double AS temperature "
        f"FROM \"{TIMESTREAM_DB}\".\"{TIMESTREAM_TABLE}\" "
        f"WHERE device_id = '{device_id}' "
        f"AND measure_name = 'temperature' "
        f"ORDER BY time DESC "
        f"LIMIT {LOOKBACK_READINGS}"
    )

    logger.info("Timestream query: %s", query)

    readings = []
    paginator = timestream_query.get_paginator("query")
    for page in paginator.paginate(QueryString=query):
        for row in page.get("Rows", []):
            data = row.get("Data", [])
            if len(data) >= 2:
                readings.append({
                    "time": data[0].get("ScalarValue", ""),
                    "temperature": float(data[1].get("ScalarValue", 0)),
                })

    # Return oldest-first for trend calculation.
    readings.reverse()
    return readings


def _compute_moving_average(values, window=5):
    """Compute a simple moving average over a list of floats.

    Parameters
    ----------
    values : list[float]
    window : int
        Number of data points per window.

    Returns
    -------
    list[float]
        Moving average values.  Length is ``len(values) - window + 1``.
    """
    if len(values) < window:
        return values  # Not enough data; return raw values.

    averages = []
    for i in range(len(values) - window + 1):
        segment = values[i : i + window]
        averages.append(sum(segment) / len(segment))
    return averages


def _compute_rate_of_change(values):
    """Calculate the average rate of change (slope) across readings.

    Uses a simple linear regression (least-squares fit) over equally
    spaced indices.  The slope represents degrees Celsius per reading
    interval.

    Parameters
    ----------
    values : list[float]
        Ordered temperature values (oldest first).

    Returns
    -------
    float
        Slope (degrees C per reading interval).  Positive means the
        temperature is rising.
    """
    n = len(values)
    if n < 2:
        return 0.0

    # Indices 0, 1, 2, ...
    x_mean = (n - 1) / 2.0
    y_mean = sum(values) / n

    numerator = 0.0
    denominator = 0.0
    for i, y in enumerate(values):
        numerator += (i - x_mean) * (y - y_mean)
        denominator += (i - x_mean) ** 2

    if denominator == 0:
        return 0.0

    return numerator / denominator


def _compute_confidence(n_readings, rate_of_change):
    """Estimate a confidence score for the prediction.

    The confidence increases with more data points and higher absolute
    rate of change (a clear trend is easier to extrapolate).

    Parameters
    ----------
    n_readings : int
        Number of readings used in the analysis.
    rate_of_change : float
        Computed slope from ``_compute_rate_of_change``.

    Returns
    -------
    float
        Confidence score in [0.0, 1.0].
    """
    # Data-volume component: reaches 0.5 at LOOKBACK_READINGS / 2 points.
    data_score = min(n_readings / max(LOOKBACK_READINGS, 1), 1.0) * 0.5

    # Trend-strength component: a rate of 0.1 C/reading gives full
    # contribution.  Diminishes for weaker trends.
    trend_score = min(abs(rate_of_change) / 0.1, 1.0) * 0.5

    return round(data_score + trend_score, 4)


def _analyse_device(device_id):
    """Run the full predictive analysis pipeline for a single device.

    Parameters
    ----------
    device_id : str

    Returns
    -------
    dict
        Prediction result with keys: ``device_id``, ``current_temp``,
        ``moving_average``, ``rate_of_change``, ``predicted_temp``,
        ``excursion_predicted``, ``excursion_type``, ``confidence``,
        ``prediction_window_minutes``, ``readings_analysed``.
    """
    readings = _query_recent_readings(device_id)
    n_readings = len(readings)

    if n_readings == 0:
        logger.warning("No readings found for device %s", device_id)
        return {
            "device_id": device_id,
            "error": "No recent readings available",
            "excursion_predicted": False,
            "confidence": 0.0,
            "readings_analysed": 0,
        }

    temperatures = [r["temperature"] for r in readings]
    current_temp = temperatures[-1]

    # Moving average (window = min(5, n_readings))
    window = min(5, n_readings)
    moving_avg = _compute_moving_average(temperatures, window=window)
    latest_avg = moving_avg[-1] if moving_avg else current_temp

    # Rate of change (degrees C per reading interval)
    rate = _compute_rate_of_change(temperatures)

    # Estimate reading interval in minutes.  If we have at least two
    # readings with parseable timestamps we compute the real interval;
    # otherwise we fall back to 1 minute.
    reading_interval_min = _estimate_interval_minutes(readings)

    # Project temperature at the end of the prediction window.
    intervals_ahead = PREDICTION_WINDOW_MINUTES / max(reading_interval_min, 0.1)
    predicted_temp = current_temp + rate * intervals_ahead

    # Determine if an excursion is predicted.
    excursion_predicted = False
    excursion_type = None

    if predicted_temp < TEMP_MIN:
        excursion_predicted = True
        excursion_type = "LOW_TEMP" if predicted_temp >= 0.0 else "FREEZE"
    elif predicted_temp > TEMP_MAX:
        excursion_predicted = True
        excursion_type = "HIGH_TEMP"

    confidence = _compute_confidence(n_readings, rate)

    result = {
        "device_id": device_id,
        "current_temp": round(current_temp, 2),
        "moving_average": round(latest_avg, 2),
        "rate_of_change_per_min": round(rate / max(reading_interval_min, 0.1), 4),
        "predicted_temp": round(predicted_temp, 2),
        "excursion_predicted": excursion_predicted,
        "excursion_type": excursion_type,
        "confidence": confidence,
        "prediction_window_minutes": PREDICTION_WINDOW_MINUTES,
        "readings_analysed": n_readings,
        "analysis_timestamp": datetime.now(timezone.utc).isoformat(),
    }

    logger.info("Prediction for %s: %s", device_id, json.dumps(result))
    return result


def _estimate_interval_minutes(readings):
    """Estimate the average interval between readings in minutes.

    Parameters
    ----------
    readings : list[dict]
        Ordered readings (oldest first) with an ISO ``time`` key.

    Returns
    -------
    float
        Estimated interval in minutes.  Defaults to 1.0 when the
        interval cannot be determined.
    """
    if len(readings) < 2:
        return 1.0

    try:
        first_time = datetime.fromisoformat(
            readings[0]["time"].replace("Z", "+00:00")
        )
        last_time = datetime.fromisoformat(
            readings[-1]["time"].replace("Z", "+00:00")
        )
        total_seconds = (last_time - first_time).total_seconds()
        intervals = len(readings) - 1
        if intervals > 0 and total_seconds > 0:
            return (total_seconds / intervals) / 60.0
    except (ValueError, TypeError) as exc:
        logger.warning("Could not parse reading timestamps: %s", exc)

    return 1.0


def _publish_warning(device_id, prediction):
    """Publish a predictive excursion warning to SNS.

    Parameters
    ----------
    device_id : str
    prediction : dict
        Prediction result from ``_analyse_device``.
    """
    if not SNS_TOPIC_ARN:
        logger.warning("SNS_TOPIC_ARN not configured; skipping warning publication.")
        return

    excursion_label = prediction.get("excursion_type", "UNKNOWN")
    subject = (
        f"[ColdTrack PREDICTED] {excursion_label} excursion - "
        f"Device {device_id}"
    )[:100]

    message_body = {
        "default": (
            f"Predicted {excursion_label} excursion for device {device_id} "
            f"within {PREDICTION_WINDOW_MINUTES} minutes. "
            f"Current temp: {prediction['current_temp']} C, "
            f"predicted temp: {prediction['predicted_temp']} C. "
            f"Confidence: {prediction['confidence']:.0%}."
        ),
        "prediction": prediction,
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
            "Published predictive warning to SNS for device %s (type=%s, confidence=%.2f)",
            device_id,
            excursion_label,
            prediction["confidence"],
        )
    except ClientError as exc:
        logger.error(
            "Failed to publish SNS warning for device %s: %s",
            device_id,
            exc,
        )
