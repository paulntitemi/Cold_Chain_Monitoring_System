#!/usr/bin/env python3

"""
ColdTrack Cold Chain Monitoring System - Enhanced Device Simulator
==================================================================

Simulates an ESP32 temperature sensor publishing telemetry data to
AWS IoT Core via MQTT over TLS. Supports multiple operational
scenarios for testing alerting, analytics, and monitoring pipelines.

Usage:
    python3 scripts/simulate-device.py \\
        --device-id ESP32_001 \\
        --endpoint <iot-endpoint>.iot.eu-west-1.amazonaws.com \\
        --cert esp32/certificates/ESP32_001/certificate.pem.crt \\
        --key esp32/certificates/ESP32_001/private.pem.key \\
        --ca esp32/certificates/ESP32_001/AmazonRootCA1.pem \\
        --scenario normal \\
        --duration 60 \\
        --interval 5

Scenarios:
    normal        - Temperature varies naturally between 2-8 C
    freeze        - Starts normal, gradually drops below 0 C
    heat          - Starts normal, gradually rises above 8 C
    battery_drain - Rapid battery drain from 100% to 0%
    intermittent  - Connects and disconnects randomly

Prerequisites:
    pip install awsiotsdk
"""

import argparse
import json
import math
import os
import random
import signal
import sys
import time
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, Optional


# ---------------------------------------------------------------------------
# Terminal colors
# ---------------------------------------------------------------------------
class Colors:
    """ANSI color codes for terminal output."""
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    CYAN = "\033[0;36m"
    MAGENTA = "\033[0;35m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    NC = "\033[0m"  # No color / reset

    @staticmethod
    def temp_color(temp: float) -> str:
        """Return a color code based on temperature value."""
        if temp < 0.0:
            return Colors.MAGENTA  # Freezing
        elif temp < 2.0:
            return Colors.BLUE     # Too cold
        elif temp <= 8.0:
            return Colors.GREEN    # Normal range
        elif temp <= 12.0:
            return Colors.YELLOW   # Warning high
        else:
            return Colors.RED      # Critical high

    @staticmethod
    def battery_color(battery: float) -> str:
        """Return a color code based on battery percentage."""
        if battery > 50.0:
            return Colors.GREEN
        elif battery > 20.0:
            return Colors.YELLOW
        else:
            return Colors.RED


# ---------------------------------------------------------------------------
# GPS Coordinate Simulator
# ---------------------------------------------------------------------------
class GPSSimulator:
    """Simulates GPS movement along a route in the Johannesburg area."""

    # A simulated route: Johannesburg -> Pretoria corridor
    ROUTE_POINTS = [
        (-26.2041, 28.0473),   # Johannesburg CBD
        (-26.1870, 28.0560),   # Braamfontein
        (-26.1496, 28.0620),   # Parktown
        (-26.1076, 28.0568),   # Rosebank
        (-26.0576, 28.0611),   # Sandton
        (-25.9976, 28.0650),   # Midrand
        (-25.8960, 28.1050),   # Centurion
        (-25.7479, 28.2293),   # Pretoria CBD
    ]

    def __init__(self):
        self.route_index = 0
        self.progress = 0.0  # 0.0 to 1.0 between current and next point

    def get_position(self) -> tuple:
        """Get current interpolated GPS position."""
        idx = self.route_index % len(self.ROUTE_POINTS)
        next_idx = (idx + 1) % len(self.ROUTE_POINTS)

        lat1, lon1 = self.ROUTE_POINTS[idx]
        lat2, lon2 = self.ROUTE_POINTS[next_idx]

        # Interpolate with some noise
        lat = lat1 + (lat2 - lat1) * self.progress + random.gauss(0, 0.0005)
        lon = lon1 + (lon2 - lon1) * self.progress + random.gauss(0, 0.0005)

        # Advance along route
        self.progress += random.uniform(0.02, 0.08)
        if self.progress >= 1.0:
            self.progress = 0.0
            self.route_index += 1

        return round(lat, 6), round(lon, 6)


# ---------------------------------------------------------------------------
# Scenario Implementations
# ---------------------------------------------------------------------------
class Scenario:
    """Base class for telemetry scenarios."""

    def __init__(self, device_id: str):
        self.device_id = device_id
        self.gps = GPSSimulator()
        self.reading_count = 0
        self.battery = 95.0 + random.uniform(-5, 5)
        self.rssi = -50 + random.randint(-20, 10)
        self.temperature = 5.0  # Starting temperature in safe zone
        self.humidity = 45.0

    def generate_reading(self, elapsed_seconds: float, total_duration: float) -> Dict[str, Any]:
        """Generate a telemetry reading. Override in subclasses."""
        raise NotImplementedError

    def _base_reading(self) -> Dict[str, Any]:
        """Build the common telemetry payload structure."""
        self.reading_count += 1
        lat, lon = self.gps.get_position()
        now = datetime.now(timezone.utc)

        return {
            "device_id": self.device_id,
            "message_id": str(uuid.uuid4()),
            "timestamp": now.isoformat(),
            "epoch_ms": int(now.timestamp() * 1000),
            "firmware_version": "1.4.2",
            "sensors": {
                "temperature": round(self.temperature, 2),
                "humidity": round(self.humidity, 1),
            },
            "power": {
                "battery_percent": round(max(0.0, self.battery), 1),
                "charging": False,
                "voltage": round(3.3 + (self.battery / 100.0) * 0.9, 2),
            },
            "connectivity": {
                "rssi_dbm": self.rssi,
                "wifi_connected": True,
                "mqtt_connected": True,
            },
            "location": {
                "latitude": lat,
                "longitude": lon,
                "altitude_m": 1500 + random.randint(-50, 50),
                "hdop": round(random.uniform(0.8, 2.5), 1),
            },
            "sequence": self.reading_count,
        }


class NormalScenario(Scenario):
    """Temperature varies naturally within 2-8 C range."""

    def __init__(self, device_id: str):
        super().__init__(device_id)
        self.temperature = random.uniform(3.0, 7.0)
        self.phase = random.uniform(0, 2 * math.pi)

    def generate_reading(self, elapsed: float, total: float) -> Dict[str, Any]:
        # Sinusoidal variation within safe zone + random noise
        self.temperature = 5.0 + 2.5 * math.sin(self.phase + elapsed * 0.05) + random.gauss(0, 0.3)
        self.temperature = max(2.0, min(8.0, self.temperature))

        self.humidity = 45.0 + 10 * math.sin(elapsed * 0.03) + random.gauss(0, 2)
        self.humidity = max(20, min(80, self.humidity))

        self.battery -= random.uniform(0.01, 0.05)
        self.rssi = -50 + random.randint(-20, 10)

        return self._base_reading()


class FreezeScenario(Scenario):
    """Temperature starts normal and gradually drops below 0 C."""

    def __init__(self, device_id: str):
        super().__init__(device_id)
        self.temperature = random.uniform(4.0, 6.0)

    def generate_reading(self, elapsed: float, total: float) -> Dict[str, Any]:
        progress = elapsed / total if total > 0 else 0

        if progress < 0.2:
            # Normal phase
            self.temperature = 5.0 + random.gauss(0, 0.5)
        elif progress < 0.5:
            # Cooling begins
            target = 5.0 - (progress - 0.2) * 20.0
            self.temperature = target + random.gauss(0, 0.3)
        else:
            # Deep freeze
            target = 5.0 - (progress - 0.2) * 25.0
            self.temperature = target + random.gauss(0, 0.2)

        self.temperature = max(-15.0, self.temperature)
        self.humidity = 60.0 + random.gauss(0, 3)
        self.battery -= random.uniform(0.02, 0.06)
        self.rssi = -55 + random.randint(-15, 10)

        return self._base_reading()


class HeatScenario(Scenario):
    """Temperature starts normal and gradually rises above 8 C."""

    def __init__(self, device_id: str):
        super().__init__(device_id)
        self.temperature = random.uniform(4.0, 6.0)

    def generate_reading(self, elapsed: float, total: float) -> Dict[str, Any]:
        progress = elapsed / total if total > 0 else 0

        if progress < 0.2:
            # Normal phase
            self.temperature = 5.0 + random.gauss(0, 0.5)
        elif progress < 0.5:
            # Warming begins
            target = 5.0 + (progress - 0.2) * 25.0
            self.temperature = target + random.gauss(0, 0.4)
        else:
            # Overheating
            target = 5.0 + (progress - 0.2) * 35.0
            self.temperature = target + random.gauss(0, 0.5)

        self.temperature = min(45.0, self.temperature)
        self.humidity = 40.0 - progress * 20 + random.gauss(0, 2)
        self.humidity = max(10, self.humidity)
        self.battery -= random.uniform(0.03, 0.08)
        self.rssi = -50 + random.randint(-20, 10)

        return self._base_reading()


class BatteryDrainScenario(Scenario):
    """Battery drains rapidly from 100% to 0% while temperature remains normal."""

    def __init__(self, device_id: str):
        super().__init__(device_id)
        self.battery = 100.0
        self.temperature = random.uniform(4.0, 6.0)

    def generate_reading(self, elapsed: float, total: float) -> Dict[str, Any]:
        progress = elapsed / total if total > 0 else 0

        # Linear battery drain with acceleration
        self.battery = 100.0 * (1.0 - progress ** 0.8)
        self.battery = max(0.0, self.battery)

        # Temperature stays normal
        self.temperature = 5.0 + 1.5 * math.sin(elapsed * 0.1) + random.gauss(0, 0.3)
        self.temperature = max(2.0, min(8.0, self.temperature))

        self.humidity = 45.0 + random.gauss(0, 3)

        # RSSI degrades as battery gets low
        if self.battery < 10:
            self.rssi = -80 + random.randint(-10, 5)
        elif self.battery < 30:
            self.rssi = -65 + random.randint(-10, 5)
        else:
            self.rssi = -50 + random.randint(-15, 10)

        return self._base_reading()


class IntermittentScenario(Scenario):
    """Connection drops and reconnects randomly."""

    def __init__(self, device_id: str):
        super().__init__(device_id)
        self.temperature = random.uniform(3.0, 7.0)
        self.is_connected = True
        self.next_toggle_at = random.uniform(5, 15)

    def should_disconnect(self, elapsed: float) -> bool:
        """Determine if the device should simulate a disconnection."""
        if elapsed >= self.next_toggle_at:
            self.is_connected = not self.is_connected
            if self.is_connected:
                self.next_toggle_at = elapsed + random.uniform(8, 20)
            else:
                self.next_toggle_at = elapsed + random.uniform(3, 10)
            return not self.is_connected
        return not self.is_connected

    def generate_reading(self, elapsed: float, total: float) -> Dict[str, Any]:
        self.temperature = 5.0 + 2.0 * math.sin(elapsed * 0.07) + random.gauss(0, 0.4)
        self.temperature = max(1.0, min(9.0, self.temperature))

        self.humidity = 45.0 + random.gauss(0, 3)
        self.battery -= random.uniform(0.02, 0.06)
        self.rssi = -55 + random.randint(-20, 10)

        reading = self._base_reading()
        reading["connectivity"]["mqtt_connected"] = self.is_connected
        return reading


# Scenario registry
SCENARIOS = {
    "normal": NormalScenario,
    "freeze": FreezeScenario,
    "heat": HeatScenario,
    "battery_drain": BatteryDrainScenario,
    "intermittent": IntermittentScenario,
}


# ---------------------------------------------------------------------------
# Device Simulator
# ---------------------------------------------------------------------------
class DeviceSimulator:
    """
    Manages the MQTT connection and telemetry publishing loop.
    Uses the AWS IoT Device SDK v2 (awscrt / awsiot).
    """

    def __init__(self, args: argparse.Namespace):
        self.device_id = args.device_id
        self.endpoint = args.endpoint
        self.cert_path = args.cert
        self.key_path = args.key
        self.ca_path = args.ca
        self.duration = args.duration
        self.interval = args.interval
        self.scenario_name = args.scenario

        self.topic = f"coldtrack/sensors/{self.device_id}/telemetry"
        self.connection = None
        self.running = False
        self.messages_sent = 0
        self.messages_failed = 0

        # Create the scenario
        scenario_cls = SCENARIOS[self.scenario_name]
        self.scenario = scenario_cls(self.device_id)

    def _print_banner(self) -> None:
        """Print startup banner."""
        print()
        print(f"{Colors.BLUE}{Colors.BOLD}{'=' * 64}{Colors.NC}")
        print(f"{Colors.BLUE}{Colors.BOLD}  ColdTrack Device Simulator{Colors.NC}")
        print(f"{Colors.BLUE}{Colors.BOLD}{'=' * 64}{Colors.NC}")
        print()
        print(f"  {Colors.DIM}Device ID : {self.device_id}{Colors.NC}")
        print(f"  {Colors.DIM}Endpoint  : {self.endpoint}{Colors.NC}")
        print(f"  {Colors.DIM}Topic     : {self.topic}{Colors.NC}")
        print(f"  {Colors.DIM}Scenario  : {self.scenario_name}{Colors.NC}")
        print(f"  {Colors.DIM}Duration  : {self.duration}s{Colors.NC}")
        print(f"  {Colors.DIM}Interval  : {self.interval}s{Colors.NC}")
        print()

    def _print_reading(self, reading: Dict[str, Any], publish_ok: bool) -> None:
        """Print a formatted telemetry reading to the console."""
        temp = reading["sensors"]["temperature"]
        humidity = reading["sensors"]["humidity"]
        battery = reading["power"]["battery_percent"]
        rssi = reading["connectivity"]["rssi_dbm"]
        lat = reading["location"]["latitude"]
        lon = reading["location"]["longitude"]
        seq = reading["sequence"]
        connected = reading["connectivity"]["mqtt_connected"]

        temp_c = Colors.temp_color(temp)
        batt_c = Colors.battery_color(battery)
        status_c = Colors.GREEN if publish_ok else Colors.RED
        status_label = "SENT" if publish_ok else "FAIL"
        conn_label = "UP" if connected else f"{Colors.RED}DOWN{Colors.NC}"

        timestamp_str = datetime.now().strftime("%H:%M:%S")

        print(
            f"  {Colors.DIM}[{timestamp_str}]{Colors.NC} "
            f"#{seq:04d} "
            f"[{status_c}{status_label}{Colors.NC}] "
            f"Temp: {temp_c}{temp:6.2f} C{Colors.NC}  "
            f"Hum: {humidity:5.1f}%  "
            f"Batt: {batt_c}{battery:5.1f}%{Colors.NC}  "
            f"RSSI: {rssi} dBm  "
            f"GPS: ({lat:.4f}, {lon:.4f})  "
            f"Conn: {conn_label}"
        )

    def connect(self) -> None:
        """Establish MQTT connection to AWS IoT Core."""
        try:
            from awscrt import io, mqtt
            from awsiot import mqtt_connection_builder
        except ImportError:
            print(f"{Colors.RED}[ERROR] awsiotsdk is not installed.{Colors.NC}")
            print(f"  Install with: pip install awsiotsdk")
            sys.exit(1)

        print(f"  {Colors.CYAN}>> Connecting to AWS IoT Core ...{Colors.NC}")

        # Initialize event loop group and host resolver
        event_loop_group = io.EventLoopGroup(1)
        host_resolver = io.DefaultHostResolver(event_loop_group)
        client_bootstrap = io.ClientBootstrap(event_loop_group, host_resolver)

        self.connection = mqtt_connection_builder.mtls_from_path(
            endpoint=self.endpoint,
            cert_filepath=self.cert_path,
            pri_key_filepath=self.key_path,
            ca_filepath=self.ca_path,
            client_bootstrap=client_bootstrap,
            client_id=self.device_id,
            clean_session=False,
            keep_alive_secs=30,
        )

        connect_future = self.connection.connect()
        connect_future.result(timeout=15)

        print(f"  {Colors.GREEN}[PASS] Connected to {self.endpoint}{Colors.NC}")
        print()

    def disconnect(self) -> None:
        """Gracefully disconnect from MQTT."""
        if self.connection is not None:
            print()
            print(f"  {Colors.CYAN}>> Disconnecting ...{Colors.NC}")
            try:
                disconnect_future = self.connection.disconnect()
                disconnect_future.result(timeout=10)
                print(f"  {Colors.GREEN}[PASS] Disconnected gracefully{Colors.NC}")
            except Exception as e:
                print(f"  {Colors.YELLOW}[WARN] Disconnect error: {e}{Colors.NC}")

    def publish(self, payload: Dict[str, Any]) -> bool:
        """Publish a JSON payload to the telemetry topic."""
        from awscrt import mqtt

        try:
            message = json.dumps(payload)
            pub_future, _ = self.connection.publish(
                topic=self.topic,
                payload=message,
                qos=mqtt.QoS.AT_LEAST_ONCE,
            )
            pub_future.result(timeout=10)
            self.messages_sent += 1
            return True
        except Exception as e:
            self.messages_failed += 1
            if "--verbose" in sys.argv or "-v" in sys.argv:
                print(f"  {Colors.RED}[ERROR] Publish failed: {e}{Colors.NC}")
            return False

    def run(self) -> None:
        """Main simulation loop."""
        self._print_banner()
        self.connect()

        self.running = True
        start_time = time.time()

        # Register signal handler for graceful shutdown
        original_sigint = signal.getsignal(signal.SIGINT)

        def _signal_handler(sig, frame):
            print()
            print(f"  {Colors.YELLOW}>> Ctrl+C received. Shutting down ...{Colors.NC}")
            self.running = False

        signal.signal(signal.SIGINT, _signal_handler)
        signal.signal(signal.SIGTERM, _signal_handler)

        print(f"  {Colors.BOLD}Publishing telemetry (Ctrl+C to stop):{Colors.NC}")
        print(f"  {Colors.DIM}{'-' * 100}{Colors.NC}")

        try:
            while self.running:
                elapsed = time.time() - start_time

                # Check if duration exceeded
                if self.duration > 0 and elapsed >= self.duration:
                    print()
                    print(f"  {Colors.CYAN}>> Duration of {self.duration}s reached.{Colors.NC}")
                    break

                # Intermittent scenario: check for disconnection
                if isinstance(self.scenario, IntermittentScenario):
                    if self.scenario.should_disconnect(elapsed):
                        reading = self.scenario.generate_reading(elapsed, self.duration)
                        self._print_reading(reading, False)
                        time.sleep(self.interval)
                        continue

                # Generate reading from scenario
                reading = self.scenario.generate_reading(elapsed, self.duration)

                # Publish
                ok = self.publish(reading)
                self._print_reading(reading, ok)

                # Wait for next interval
                time.sleep(self.interval)

        finally:
            # Restore original signal handler
            signal.signal(signal.SIGINT, original_sigint)

            self.disconnect()
            self._print_summary()

    def _print_summary(self) -> None:
        """Print final summary statistics."""
        elapsed = time.time() if not hasattr(self, "_start_time") else time.time() - self._start_time
        total = self.messages_sent + self.messages_failed

        print()
        print(f"{Colors.BLUE}{Colors.BOLD}{'=' * 64}{Colors.NC}")
        print(f"{Colors.BLUE}{Colors.BOLD}  Simulation Summary{Colors.NC}")
        print(f"{Colors.BLUE}{Colors.BOLD}{'=' * 64}{Colors.NC}")
        print()
        print(f"  Device ID      : {self.device_id}")
        print(f"  Scenario       : {self.scenario_name}")
        print(f"  Messages Sent  : {Colors.GREEN}{self.messages_sent}{Colors.NC}")
        print(f"  Messages Failed: {Colors.RED if self.messages_failed > 0 else Colors.DIM}{self.messages_failed}{Colors.NC}")
        print(f"  Total Attempted: {total}")
        if total > 0:
            success_rate = (self.messages_sent / total) * 100
            rate_color = Colors.GREEN if success_rate > 95 else Colors.YELLOW if success_rate > 80 else Colors.RED
            print(f"  Success Rate   : {rate_color}{success_rate:.1f}%{Colors.NC}")
        print()


# ---------------------------------------------------------------------------
# Argument Parser
# ---------------------------------------------------------------------------
def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="ColdTrack ESP32 Device Simulator - Simulates IoT sensor telemetry",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Scenarios:
  normal          Temperature varies naturally between 2-8 C (safe zone)
  freeze          Temperature starts normal, gradually drops below 0 C
  heat            Temperature starts normal, gradually rises above 8 C
  battery_drain   Battery drains rapidly from 100%% to 0%%
  intermittent    Device connects and disconnects randomly

Examples:
  %(prog)s --device-id ESP32_001 --endpoint <endpoint> --cert cert.pem --key key.pem --ca ca.pem
  %(prog)s --device-id ESP32_002 --endpoint <endpoint> --cert cert.pem --key key.pem --ca ca.pem --scenario freeze --duration 120
  %(prog)s --device-id ESP32_003 --endpoint <endpoint> --cert cert.pem --key key.pem --ca ca.pem --scenario heat --interval 2
        """,
    )

    parser.add_argument(
        "--device-id",
        required=True,
        help="Unique device identifier (e.g., ESP32_001)",
    )
    parser.add_argument(
        "--endpoint",
        required=True,
        help="AWS IoT Core endpoint (e.g., <id>-ats.iot.eu-west-1.amazonaws.com)",
    )
    parser.add_argument(
        "--cert",
        required=True,
        help="Path to the device certificate PEM file",
    )
    parser.add_argument(
        "--key",
        required=True,
        help="Path to the device private key PEM file",
    )
    parser.add_argument(
        "--ca",
        required=True,
        help="Path to the Amazon Root CA PEM file",
    )
    parser.add_argument(
        "--scenario",
        choices=list(SCENARIOS.keys()),
        default="normal",
        help="Simulation scenario (default: normal)",
    )
    parser.add_argument(
        "--duration",
        type=int,
        default=60,
        help="Duration in seconds to run the simulation (default: 60, 0 = unlimited)",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=5.0,
        help="Publish interval in seconds (default: 5.0)",
    )

    args = parser.parse_args()

    # Validate file paths
    for label, path in [("Certificate", args.cert), ("Private key", args.key), ("CA", args.ca)]:
        if not os.path.isfile(path):
            parser.error(f"{label} file not found: {path}")

    return args


# ---------------------------------------------------------------------------
# Entry Point
# ---------------------------------------------------------------------------
def main() -> None:
    """Entry point for the device simulator."""
    args = parse_args()

    simulator = DeviceSimulator(args)

    try:
        simulator.run()
    except KeyboardInterrupt:
        pass
    except Exception as e:
        print(f"\n  {Colors.RED}[ERROR] Simulation failed: {e}{Colors.NC}")
        sys.exit(1)


if __name__ == "__main__":
    main()
