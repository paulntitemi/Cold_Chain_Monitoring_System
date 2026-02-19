#!/usr/bin/env python3
"""
ColdTrack IoT Connection Test
Tests MQTT connectivity to AWS IoT Core using device certificates.

Usage:
    python3 test-iot-connection.py
    python3 test-iot-connection.py --endpoint YOUR_ENDPOINT --cert path/to/cert --key path/to/key --ca path/to/ca
"""

import argparse
import json
import os
import sys
import time

try:
    from awscrt import mqtt
    from awsiot import mqtt_connection_builder
except ImportError:
    print("ERROR: AWS IoT SDK not installed")
    print("Run: pip install awsiotsdk")
    sys.exit(1)


# Default paths — update these or pass via CLI args
DEFAULT_ENDPOINT = "amfou4arkp5l-ats.iot.eu-west-1.amazonaws.com"
DEFAULT_CLIENT_ID = "ESP32_TEST_002"
DEFAULT_CERT_PATH = "../esp32/certificates/device-certificate.pem.crt"
DEFAULT_KEY_PATH = "../esp32/certificates/private-key.pem.key"
DEFAULT_CA_PATH = "../esp32/certificates/AmazonRootCA1.pem"


def on_connection_success(connection, callback_data):
    print("[PASS] Connected to AWS IoT Core!")


def on_connection_failure(connection, callback_data):
    print("[FAIL] Connection failed")


def on_connection_interrupted(connection, error, **kwargs):
    print(f"[WARN] Connection interrupted: {error}")


def on_connection_resumed(connection, return_code, session_present, **kwargs):
    print(f"[INFO] Connection resumed (rc={return_code})")


def run_connection_test(endpoint, client_id, cert_path, key_path, ca_path):
    """Test basic MQTT connection to AWS IoT Core."""
    print("=" * 60)
    print("  ColdTrack IoT Connection Test")
    print("=" * 60)
    print(f"  Endpoint:  {endpoint}")
    print(f"  Client ID: {client_id}")
    print(f"  Cert:      {cert_path}")
    print(f"  Key:       {key_path}")
    print(f"  CA:        {ca_path}")
    print("=" * 60)

    # Validate files exist
    for label, path in [("Certificate", cert_path), ("Private key", key_path), ("Root CA", ca_path)]:
        if not os.path.isfile(path):
            print(f"\n[FAIL] {label} not found: {path}")
            print("  Make sure you have provisioned the device and downloaded certificates.")
            print("  Run: ./scripts/provision-device.sh ESP32_TEST_002")
            return False

    # Build MQTT connection
    print(f"\n[INFO] Connecting to {endpoint}...")
    try:
        mqtt_connection = mqtt_connection_builder.mtls_from_path(
            endpoint=endpoint,
            cert_filepath=cert_path,
            pri_key_filepath=key_path,
            ca_filepath=ca_path,
            client_id=client_id,
            clean_session=False,
            keep_alive_secs=30,
            on_connection_success=on_connection_success,
            on_connection_failure=on_connection_failure,
            on_connection_interrupted=on_connection_interrupted,
            on_connection_resumed=on_connection_resumed,
        )

        connect_future = mqtt_connection.connect()
        connect_future.result(timeout=10)
        print("[PASS] MQTT connection established\n")
    except Exception as e:
        print(f"[FAIL] Could not connect: {e}")
        print("\nTroubleshooting:")
        print("  1. Verify your IoT endpoint is correct")
        print("  2. Check that certificates are valid and active")
        print("  3. Ensure the IoT policy is attached to the certificate")
        print("  4. Confirm the certificate is attached to the IoT Thing")
        return False

    # Publish test telemetry message
    telemetry_topic = f"coldtrack/sensors/{client_id}/telemetry"
    telemetry_msg = {
        "device_id": client_id,
        "temperature": 5.2,
        "humidity": 65.0,
        "battery": 87.0,
        "latitude": -33.9249,
        "longitude": 18.4241,
        "rssi": -62,
        "timestamp": int(time.time()),
        "test": True,
    }

    print(f"[INFO] Publishing telemetry to: {telemetry_topic}")
    pub_future, _ = mqtt_connection.publish(
        topic=telemetry_topic,
        payload=json.dumps(telemetry_msg),
        qos=mqtt.QoS.AT_LEAST_ONCE,
    )
    pub_future.result(timeout=5)
    print("[PASS] Telemetry message published")

    # Publish test alert message
    alert_topic = f"coldtrack/sensors/{client_id}/alerts"
    alert_msg = {
        "device_id": client_id,
        "temperature": 9.5,
        "alert_type": "HIGH_TEMP",
        "severity": "WARNING",
        "message": "Test alert: temperature above threshold",
        "timestamp": int(time.time()),
        "test": True,
    }

    print(f"[INFO] Publishing alert to: {alert_topic}")
    pub_future, _ = mqtt_connection.publish(
        topic=alert_topic,
        payload=json.dumps(alert_msg),
        qos=mqtt.QoS.AT_LEAST_ONCE,
    )
    pub_future.result(timeout=5)
    print("[PASS] Alert message published")

    # Subscribe to command topic
    command_topic = f"coldtrack/commands/{client_id}"
    print(f"[INFO] Subscribing to: {command_topic}")

    def on_message(topic, payload, **kwargs):
        msg = json.loads(payload)
        print(f"[RECV] Command received on {topic}: {json.dumps(msg, indent=2)}")

    sub_future, _ = mqtt_connection.subscribe(
        topic=command_topic,
        qos=mqtt.QoS.AT_LEAST_ONCE,
        callback=on_message,
    )
    sub_future.result(timeout=5)
    print("[PASS] Subscribed to command topic")

    # Wait briefly for any incoming messages
    print("\n[INFO] Waiting 3 seconds for incoming messages...")
    time.sleep(3)

    # Disconnect
    print("[INFO] Disconnecting...")
    disconnect_future = mqtt_connection.disconnect()
    disconnect_future.result(timeout=5)
    print("[PASS] Disconnected cleanly")

    # Summary
    print("\n" + "=" * 60)
    print("  ALL TESTS PASSED")
    print("=" * 60)
    print("  Your device can connect, publish, and subscribe.")
    print("  Next steps:")
    print("    1. Check AWS IoT Console > MQTT test client")
    print("       Subscribe to: coldtrack/sensors/#")
    print("    2. Run the full simulator:")
    print("       python3 scripts/simulate-device.py \\")
    print(f"         --device-id {client_id} \\")
    print(f"         --endpoint {endpoint} \\")
    print(f"         --cert {cert_path} \\")
    print(f"         --key {key_path} \\")
    print(f"         --ca {ca_path}")
    print("=" * 60)
    return True


def main():
    parser = argparse.ArgumentParser(description="ColdTrack IoT Connection Test")
    parser.add_argument("--endpoint", default=DEFAULT_ENDPOINT, help="AWS IoT endpoint")
    parser.add_argument("--client-id", default=DEFAULT_CLIENT_ID, help="MQTT client ID")
    parser.add_argument("--cert", default=DEFAULT_CERT_PATH, help="Path to device certificate")
    parser.add_argument("--key", default=DEFAULT_KEY_PATH, help="Path to private key")
    parser.add_argument("--ca", default=DEFAULT_CA_PATH, help="Path to Amazon Root CA")
    args = parser.parse_args()

    success = run_connection_test(args.endpoint, args.client_id, args.cert, args.key, args.ca)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
