#!/usr/bin/env python3
"""
ColdTrack Storage Pipeline Test

Verifies the end-to-end data flow:
    ESP32 → IoT Core → Lambda → Timestream
                      → IoT Rule → Firehose → S3

Usage:
    python3 tests/test-storage-pipeline.py
    python3 tests/test-storage-pipeline.py --skip-s3   # Skip S3/Firehose check (takes 60s+)
"""

import argparse
import gzip
import json
import os
import sys
import time
from datetime import datetime, timezone

try:
    import boto3
    from botocore.exceptions import ClientError
except ImportError:
    print("ERROR: boto3 not installed. Run: pip install boto3")
    sys.exit(1)

try:
    from awscrt import mqtt
    from awsiot import mqtt_connection_builder
except ImportError:
    print("ERROR: AWS IoT SDK not installed. Run: pip install awsiotsdk")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Configuration (reads from .env or defaults)
# ---------------------------------------------------------------------------
REGION = os.environ.get("AWS_REGION", "eu-west-1")
IOT_ENDPOINT = os.environ.get("AWS_IOT_ENDPOINT", "amfou4arkp5l-ats.iot.eu-west-1.amazonaws.com")
ACCOUNT_ID = os.environ.get("AWS_ACCOUNT_ID", "825765428301")

DEVICE_ID = "ESP32_TEST_002"
CERT_DIR = os.path.join(os.path.dirname(__file__), "..", "esp32", "certificates")
CERT_PATH = os.path.join(CERT_DIR, "device-certificate.pem.crt")
KEY_PATH = os.path.join(CERT_DIR, "private-key.pem.key")
CA_PATH = os.path.join(CERT_DIR, "AmazonRootCA1.pem")

TIMESTREAM_DB = "coldtrack-telemetry"
TIMESTREAM_TABLE = "sensor_data"
S3_RAW_BUCKET = f"coldtrack-raw-data-{ACCOUNT_ID}-{REGION}"
FIREHOSE_STREAM = "coldtrack-telemetry-to-s3"

# Colours
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
RED = "\033[0;31m"
NC = "\033[0m"

passed = 0
failed = 0


def ok(msg):
    global passed
    passed += 1
    print(f"  {GREEN}[PASS]{NC} {msg}")


def fail(msg):
    global failed
    failed += 1
    print(f"  {RED}[FAIL]{NC} {msg}")


def info(msg):
    print(f"  {YELLOW}[INFO]{NC} {msg}")


def header(msg):
    print(f"\n{YELLOW}{'━' * 60}{NC}")
    print(f"  {msg}")
    print(f"{YELLOW}{'━' * 60}{NC}")


# ===================================================================
# Test 1: Publish test telemetry via MQTT
# ===================================================================
def publish_test_telemetry():
    """Publish a test message and return the payload for later verification."""
    header("Test 1: Publish Telemetry via MQTT")

    test_timestamp = int(time.time())
    test_marker = f"test-{test_timestamp}"

    # Telemetry in the flat format the Lambda expects
    payload = {
        "device_id": DEVICE_ID,
        "temperature": 4.75,
        "humidity": 58.3,
        "battery": 92.0,
        "latitude": -26.2041,
        "longitude": 28.0473,
        "rssi": -55,
        "timestamp": test_timestamp,
        "test_marker": test_marker,
    }

    info(f"Connecting to IoT Core: {IOT_ENDPOINT}")
    try:
        connection = mqtt_connection_builder.mtls_from_path(
            endpoint=IOT_ENDPOINT,
            cert_filepath=CERT_PATH,
            pri_key_filepath=KEY_PATH,
            ca_filepath=CA_PATH,
            client_id=f"{DEVICE_ID}-storage-test",
            clean_session=True,
            keep_alive_secs=30,
        )
        connection.connect().result(timeout=10)
        ok("MQTT connected")
    except Exception as e:
        fail(f"MQTT connection failed: {e}")
        return None

    topic = f"coldtrack/sensors/{DEVICE_ID}/telemetry"
    info(f"Publishing to: {topic}")
    info(f"Payload: temp={payload['temperature']}C, humidity={payload['humidity']}%, battery={payload['battery']}%")

    try:
        pub_future, _ = connection.publish(
            topic=topic,
            payload=json.dumps(payload),
            qos=mqtt.QoS.AT_LEAST_ONCE,
        )
        pub_future.result(timeout=5)
        ok(f"Telemetry published (marker: {test_marker})")
    except Exception as e:
        fail(f"Publish failed: {e}")
        connection.disconnect().result(timeout=5)
        return None

    # Send a few more messages to ensure Firehose has data to batch
    for i in range(4):
        extra = payload.copy()
        extra["temperature"] = round(4.0 + i * 0.5, 2)
        extra["timestamp"] = test_timestamp + i + 1
        connection.publish(
            topic=topic,
            payload=json.dumps(extra),
            qos=mqtt.QoS.AT_LEAST_ONCE,
        )
    ok("Published 4 additional messages for Firehose batching")

    connection.disconnect().result(timeout=5)
    return payload


# ===================================================================
# Test 2: Verify data in Timestream
# ===================================================================
def verify_timestream(payload):
    header("Test 2: Verify Timestream Storage")

    if payload is None:
        fail("Skipping — no test payload (MQTT failed)")
        return

    info("Waiting 15s for Lambda to process and write to Timestream...")
    time.sleep(15)

    try:
        ts_query = boto3.client("timestream-query", region_name=REGION)
    except Exception as e:
        fail(f"Could not create Timestream query client: {e}")
        return

    query = f"""
        SELECT device_id, measure_name, measure_value::double, time
        FROM "{TIMESTREAM_DB}"."{TIMESTREAM_TABLE}"
        WHERE device_id = '{DEVICE_ID}'
          AND time >= ago(5m)
        ORDER BY time DESC
        LIMIT 20
    """

    info(f"Querying Timestream: {TIMESTREAM_DB}.{TIMESTREAM_TABLE}")
    try:
        result = ts_query.query(QueryString=query)
        rows = result.get("Rows", [])

        if len(rows) == 0:
            fail("No records found in Timestream for this device in the last 5 minutes")
            info("Possible causes:")
            info("  - Lambda may not have Timestream write permissions")
            info("  - Lambda env vars TIMESTREAM_DB / TIMESTREAM_TABLE may be wrong")
            info("  - Check CloudWatch logs: /aws/lambda/coldtrack-processor")
            return

        ok(f"Found {len(rows)} records in Timestream")

        # Display a few records
        columns = [col["Name"] for col in result["ColumnInfo"]]
        info(f"  Columns: {', '.join(columns)}")
        for row in rows[:6]:
            values = [d.get("ScalarValue", "NULL") for d in row["Data"]]
            info(f"  {' | '.join(values)}")

        # Check that temperature measure exists
        measures = set()
        for row in rows:
            measure_name = row["Data"][1].get("ScalarValue", "")
            measures.add(measure_name)

        expected = {"temperature", "humidity", "battery", "rssi"}
        found = expected & measures
        if found:
            ok(f"Found expected measures: {', '.join(sorted(found))}")
        else:
            fail(f"Expected measures {expected} but found {measures}")

    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        error_msg = e.response["Error"]["Message"]
        fail(f"Timestream query failed: [{error_code}] {error_msg}")
        if "AccessDenied" in error_code:
            info("Your AWS credentials may not have timestream:Select permission")


# ===================================================================
# Test 3: Verify Firehose → S3 delivery
# ===================================================================
def verify_s3_delivery():
    header("Test 3: Verify Firehose → S3 Delivery")

    s3 = boto3.client("s3", region_name=REGION)

    # Check bucket exists
    try:
        s3.head_bucket(Bucket=S3_RAW_BUCKET)
        ok(f"S3 bucket '{S3_RAW_BUCKET}' exists")
    except ClientError:
        fail(f"S3 bucket '{S3_RAW_BUCKET}' not found — run setup-storage.sh first")
        return

    # Check Firehose stream status
    firehose = boto3.client("firehose", region_name=REGION)
    try:
        stream = firehose.describe_delivery_stream(DeliveryStreamName=FIREHOSE_STREAM)
        status = stream["DeliveryStreamDescription"]["DeliveryStreamStatus"]
        if status == "ACTIVE":
            ok(f"Firehose stream '{FIREHOSE_STREAM}' is ACTIVE")
        else:
            fail(f"Firehose stream status: {status} (expected ACTIVE)")
            return
    except ClientError:
        fail(f"Firehose stream '{FIREHOSE_STREAM}' not found — run setup-storage.sh first")
        return

    # Firehose buffers data — wait for flush (buffer is 60s in setup script)
    info("Waiting 75s for Firehose to flush buffer to S3...")
    info("(Firehose batches messages and writes every 60s or 1MB)")
    for remaining in range(75, 0, -15):
        info(f"  {remaining}s remaining...")
        time.sleep(15)

    # Check for objects in the telemetry/ prefix
    now = datetime.now(timezone.utc)
    prefix = f"telemetry/year={now.year}/month={now.month:02d}/day={now.day:02d}/"

    info(f"Checking S3 prefix: s3://{S3_RAW_BUCKET}/{prefix}")
    try:
        response = s3.list_objects_v2(Bucket=S3_RAW_BUCKET, Prefix=prefix, MaxKeys=10)
        objects = response.get("Contents", [])

        if len(objects) == 0:
            fail("No objects found in S3 for today's date")
            info("Possible causes:")
            info("  - Firehose may still be buffering (try again in a minute)")
            info("  - IoT rule may not be routing to Firehose")
            info("  - Check CloudWatch: /aws/kinesisfirehose/coldtrack-telemetry-to-s3")

            # Also check for any objects at all
            all_response = s3.list_objects_v2(Bucket=S3_RAW_BUCKET, Prefix="telemetry/", MaxKeys=5)
            all_objects = all_response.get("Contents", [])
            if all_objects:
                info(f"Found {len(all_objects)} objects under telemetry/ from other dates:")
                for obj in all_objects[:3]:
                    info(f"  {obj['Key']} ({obj['Size']} bytes)")
            return

        ok(f"Found {len(objects)} objects in S3")

        # Read the most recent object and display contents
        latest = sorted(objects, key=lambda x: x["LastModified"], reverse=True)[0]
        info(f"Latest file: {latest['Key']} ({latest['Size']} bytes)")

        obj_data = s3.get_object(Bucket=S3_RAW_BUCKET, Key=latest["Key"])
        body = obj_data["Body"].read()

        # Decompress if GZIP
        try:
            body = gzip.decompress(body)
            info("  (GZIP decompressed)")
        except Exception:
            pass

        # Parse NDJSON lines
        lines = body.decode("utf-8").strip().split("\n")
        ok(f"File contains {len(lines)} telemetry records")

        # Show first record
        if lines:
            try:
                first_record = json.loads(lines[0])
                info(f"  Sample record: {json.dumps(first_record, indent=2)[:300]}")
            except json.JSONDecodeError:
                info(f"  Raw content (first 200 chars): {lines[0][:200]}")

    except ClientError as e:
        fail(f"S3 list/read failed: {e}")


# ===================================================================
# Test 4: Check Lambda CloudWatch logs
# ===================================================================
def check_lambda_logs():
    header("Test 4: Lambda CloudWatch Logs")

    logs = boto3.client("logs", region_name=REGION)
    log_group = "/aws/lambda/coldtrack-processor"

    try:
        # Get latest log stream
        streams = logs.describe_log_streams(
            logGroupName=log_group,
            orderBy="LastEventTime",
            descending=True,
            limit=1,
        )

        if not streams.get("logStreams"):
            fail(f"No log streams found in {log_group}")
            return

        stream_name = streams["logStreams"][0]["logStreamName"]
        ok(f"Found log stream: {stream_name}")

        # Get recent events
        events = logs.get_log_events(
            logGroupName=log_group,
            logStreamName=stream_name,
            limit=20,
            startFromHead=False,
        )

        log_events = events.get("events", [])
        if not log_events:
            fail("No recent log events")
            return

        ok(f"Found {len(log_events)} recent log entries")

        # Look for success/error indicators
        has_timestream_write = False
        has_errors = False

        for event in log_events:
            msg = event["message"]
            if "Wrote" in msg and "Timestream" in msg:
                has_timestream_write = True
            if "ERROR" in msg or "Error" in msg:
                has_errors = True
                info(f"  ERROR: {msg.strip()[:150]}")

        if has_timestream_write:
            ok("Lambda is successfully writing to Timestream")
        else:
            info("No Timestream write confirmation found in recent logs")
            info("(Lambda may not have been invoked yet, or logs haven't propagated)")

        if has_errors:
            fail("Errors detected in Lambda logs — check CloudWatch for details")

        # Show last 5 log entries
        info("Recent log entries:")
        for event in log_events[-5:]:
            timestamp = datetime.fromtimestamp(
                event["timestamp"] / 1000, tz=timezone.utc
            ).strftime("%H:%M:%S")
            msg = event["message"].strip()[:120]
            info(f"  [{timestamp}] {msg}")

    except ClientError as e:
        if "ResourceNotFoundException" in str(e):
            fail(f"Log group '{log_group}' not found — Lambda may not have been invoked yet")
        else:
            fail(f"CloudWatch error: {e}")


# ===================================================================
# Main
# ===================================================================
def main():
    parser = argparse.ArgumentParser(description="ColdTrack Storage Pipeline Test")
    parser.add_argument("--skip-s3", action="store_true",
                        help="Skip S3/Firehose verification (avoids 75s wait)")
    args = parser.parse_args()

    print(f"\n{GREEN}{'=' * 60}{NC}")
    print(f"  ColdTrack Storage Pipeline Test")
    print(f"  {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
    print(f"{GREEN}{'=' * 60}{NC}")
    print(f"  Timestream:  {TIMESTREAM_DB}/{TIMESTREAM_TABLE}")
    print(f"  S3 Bucket:   {S3_RAW_BUCKET}")
    print(f"  Firehose:    {FIREHOSE_STREAM}")
    print(f"  Device:      {DEVICE_ID}")

    # Run tests
    payload = publish_test_telemetry()
    verify_timestream(payload)

    if not args.skip_s3:
        verify_s3_delivery()
    else:
        info("Skipping S3/Firehose test (--skip-s3 flag)")

    check_lambda_logs()

    # Summary
    print(f"\n{GREEN}{'=' * 60}{NC}")
    total = passed + failed
    if failed == 0:
        print(f"  {GREEN}ALL {total} CHECKS PASSED{NC}")
    else:
        print(f"  {passed}/{total} passed, {RED}{failed} failed{NC}")
    print(f"{'=' * 60}\n")

    if failed == 0:
        print("  Your storage pipeline is working! Next steps:")
        print("    1. Set up Grafana to visualise Timestream data")
        print("    2. Run the simulator for continuous data:")
        print("       python3 scripts/simulate-device.py")
        print("    3. Export S3 data for ML training:")
        print(f"       aws s3 sync s3://{S3_RAW_BUCKET}/telemetry/ ./data/raw/")
        print()

    sys.exit(1 if failed > 0 else 0)


if __name__ == "__main__":
    main()
