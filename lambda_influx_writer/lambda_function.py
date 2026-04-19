import json
import os
import time
from datetime import datetime, timezone

from influxdb_client import InfluxDBClient, Point, WritePrecision
from influxdb_client.client.write_api import SYNCHRONOUS


INFLUX_URL = os.environ["INFLUX_URL"]
INFLUX_TOKEN = os.environ["INFLUX_TOKEN"]
INFLUX_ORG = os.environ["INFLUX_ORG"]
INFLUX_BUCKET = os.environ["INFLUX_BUCKET"]


def lambda_handler(event, context):
    print("Received event:", json.dumps(event))

    telemetry = normalize_event(event)

    client = InfluxDBClient(
        url=INFLUX_URL,
        token=INFLUX_TOKEN,
        org=INFLUX_ORG,
    )

    try:
        point = (
            Point("sensor_data")
            .tag("device_id", telemetry["device_id"])
            .field("temperature", telemetry["temperature"])
            .field("humidity", telemetry["humidity"])
            .field("battery", telemetry["battery"])
            .field("rssi", telemetry["rssi"])
            .time(telemetry["timestamp_ms"], WritePrecision.MS)
        )

        if telemetry.get("latitude") is not None:
            point.field("latitude", telemetry["latitude"])

        if telemetry.get("longitude") is not None:
            point.field("longitude", telemetry["longitude"])

        write_api = client.write_api(write_options=SYNCHRONOUS)
        write_api.write(bucket=INFLUX_BUCKET, record=point)

        print(
            "Wrote telemetry to InfluxDB: "
            f"{telemetry['device_id']} {telemetry['temperature']}C"
        )

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": "Telemetry written to InfluxDB",
                    "device_id": telemetry["device_id"],
                }
            ),
        }

    finally:
        client.close()


def normalize_event(event):
    sensors = event.get("sensors") or {}
    power = event.get("power") or {}
    connectivity = event.get("connectivity") or {}
    location = event.get("location") or {}

    device_id = event.get("device_id") or "unknown"

    temperature = sensors.get("temperature", event.get("temperature"))
    humidity = sensors.get("humidity", event.get("humidity"))
    battery = power.get("battery_percent", event.get("battery", 100))
    rssi = connectivity.get("rssi_dbm", event.get("rssi", 0))

    latitude = location.get("latitude", event.get("latitude"))
    longitude = location.get("longitude", event.get("longitude"))

    timestamp_ms = event.get("epoch_ms")
    if timestamp_ms is None:
        timestamp_ms = parse_timestamp_to_ms(event.get("timestamp"))

    return {
        "device_id": str(device_id),
        "temperature": float(temperature),
        "humidity": float(humidity),
        "battery": float(battery),
        "rssi": int(rssi),
        "latitude": float(latitude) if latitude is not None else None,
        "longitude": float(longitude) if longitude is not None else None,
        "timestamp_ms": int(timestamp_ms),
    }


def parse_timestamp_to_ms(value):
    if value is None:
        return int(time.time() * 1000)

    if isinstance(value, (int, float)):
        if value > 10_000_000_000:
            return int(value)
        return int(value * 1000)

    if isinstance(value, str):
        try:
            numeric = float(value)
            if numeric > 10_000_000_000:
                return int(numeric)
            return int(numeric * 1000)
        except ValueError:
            pass

        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return int(parsed.timestamp() * 1000)

    return int(datetime.now(timezone.utc).timestamp() * 1000)
