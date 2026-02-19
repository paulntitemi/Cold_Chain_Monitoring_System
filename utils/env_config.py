#!/usr/bin/env python3
"""
ColdTrack Environment Configuration Loader

Loads configuration from the project .env file and provides typed access
to all settings needed for IoT connectivity testing and device simulation.

Usage:
    from utils.env_config import get_config

    config = get_config()
    print(config.aws_iot_endpoint)
    print(config.certificate_path)

Standalone:
    python3 -m utils.env_config          # from project root
    python3 utils/env_config.py          # direct execution
"""

import os
import sys
from pathlib import Path


def _find_project_root() -> Path:
    """Walk up from this file to find the project root (contains .env)."""
    current = Path(__file__).resolve().parent
    for _ in range(5):
        if (current / ".env").is_file():
            return current
        current = current.parent
    return Path(__file__).resolve().parent.parent


def _load_env_file(env_path: Path) -> dict:
    """Parse a .env file into a dict. Skips comments and blank lines."""
    values = {}
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip()
    return values


class Config:
    """Typed configuration loaded from the project .env file."""

    def __init__(self, env_path: Path = None):
        self.project_root = _find_project_root()

        if env_path is None:
            env_path = self.project_root / ".env"

        if not env_path.is_file():
            raise FileNotFoundError(f".env file not found at {env_path}")

        self._raw = _load_env_file(env_path)

        # AWS IoT Core
        self.aws_iot_endpoint = self._raw.get("AWS_IOT_ENDPOINT", "")
        self.aws_region = self._raw.get("AWS_REGION", "eu-west-1")
        self.aws_account_id = self._raw.get("AWS_ACCOUNT_ID", "")

        # Device identity
        self.device_id = self._raw.get("DEVICE_ID", "ESP32_TEST_002")
        self.client_id = self._raw.get("CLIENT_ID", self.device_id)

        # Certificate paths (resolve relative to project root)
        self.cert_dir = self._resolve(self._raw.get("CERT_DIR", "esp32/certificates/"))
        self.root_ca_path = self._resolve(self._raw.get("ROOT_CA_PATH", ""))
        self.certificate_path = self._resolve(self._raw.get("CERTIFICATE_PATH", ""))
        self.private_key_path = self._resolve(self._raw.get("PRIVATE_KEY_PATH", ""))

        # MQTT topics
        self.telemetry_topic = self._raw.get(
            "TELEMETRY_TOPIC", f"coldtrack/sensors/{self.device_id}/telemetry"
        )
        self.alerts_topic = self._raw.get(
            "ALERTS_TOPIC", f"coldtrack/sensors/{self.device_id}/alerts"
        )
        self.commands_topic = self._raw.get(
            "COMMANDS_TOPIC", f"coldtrack/commands/{self.device_id}"
        )

        # Temperature thresholds
        self.temp_max = float(self._raw.get("TEMP_MAX", "8.0"))
        self.temp_min = float(self._raw.get("TEMP_MIN", "0.0"))

        # Alert config
        self.alert_email = self._raw.get("ALERT_EMAIL", "")

        # Environment
        self.environment = self._raw.get("ENVIRONMENT", "development")

    def _resolve(self, rel_path: str) -> str:
        """Resolve a path relative to the project root. Return as string."""
        if not rel_path:
            return ""
        p = Path(rel_path)
        if p.is_absolute():
            return str(p)
        return str(self.project_root / p)

    def validate(self) -> list:
        """Check that required fields are set and certificates exist.

        Returns a list of error strings. Empty list means all OK.
        """
        errors = []

        # Endpoint
        if not self.aws_iot_endpoint:
            errors.append("AWS_IOT_ENDPOINT is not set")
        elif "YOUR" in self.aws_iot_endpoint.upper() or "PLACEHOLDER" in self.aws_iot_endpoint.upper():
            errors.append(f"AWS_IOT_ENDPOINT looks like a placeholder: {self.aws_iot_endpoint}")

        # Region
        if not self.aws_region:
            errors.append("AWS_REGION is not set")

        # Device ID
        if not self.device_id:
            errors.append("DEVICE_ID is not set")

        # Certificate files
        for label, path in [
            ("ROOT_CA_PATH (AmazonRootCA1.pem)", self.root_ca_path),
            ("CERTIFICATE_PATH (device cert)", self.certificate_path),
            ("PRIVATE_KEY_PATH (private key)", self.private_key_path),
        ]:
            if not path:
                errors.append(f"{label} is not set")
            elif not os.path.isfile(path):
                errors.append(f"{label} file not found: {path}")
            elif os.path.getsize(path) == 0:
                errors.append(f"{label} file is empty: {path}")

        return errors

    def print_summary(self):
        """Print a formatted configuration summary."""
        errors = self.validate()

        print("=" * 60)
        print("  ColdTrack Configuration Summary")
        print("=" * 60)
        print(f"  Project Root : {self.project_root}")
        print(f"  Environment  : {self.environment}")
        print()
        print(f"  AWS Region   : {self.aws_region}")
        print(f"  IoT Endpoint : {self.aws_iot_endpoint}")
        print(f"  Account ID   : {self.aws_account_id}")
        print()
        print(f"  Device ID    : {self.device_id}")
        print(f"  Client ID    : {self.client_id}")
        print()
        print(f"  Root CA      : {self.root_ca_path}")
        _file_status(self.root_ca_path)
        print(f"  Certificate  : {self.certificate_path}")
        _file_status(self.certificate_path)
        print(f"  Private Key  : {self.private_key_path}")
        _file_status(self.private_key_path)
        print()
        print(f"  Telemetry    : {self.telemetry_topic}")
        print(f"  Alerts       : {self.alerts_topic}")
        print(f"  Commands     : {self.commands_topic}")
        print()
        print(f"  Temp Range   : {self.temp_min} - {self.temp_max} C")
        print("=" * 60)

        if errors:
            print()
            print(f"  VALIDATION: {len(errors)} error(s) found:")
            for err in errors:
                print(f"    [FAIL] {err}")
            print()
        else:
            print()
            print("  VALIDATION: All checks passed")
            print()

        return len(errors) == 0


def _file_status(path: str):
    """Print file existence/size status."""
    if not path:
        print("                 -> (not set)")
    elif os.path.isfile(path):
        size = os.path.getsize(path)
        print(f"                 -> OK ({size} bytes)")
    else:
        print(f"                 -> MISSING")


# Singleton
_config_instance = None


def get_config(env_path: Path = None) -> Config:
    """Get or create the singleton Config instance."""
    global _config_instance
    if _config_instance is None:
        _config_instance = Config(env_path)
    return _config_instance


if __name__ == "__main__":
    try:
        config = Config()
        ok = config.print_summary()
        sys.exit(0 if ok else 1)
    except FileNotFoundError as e:
        print(f"[ERROR] {e}")
        sys.exit(1)
