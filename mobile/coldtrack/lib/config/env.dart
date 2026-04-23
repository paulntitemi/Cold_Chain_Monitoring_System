import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed wrapper around flutter_dotenv so the rest of the codebase does not
/// reach into `dotenv.env['...']` with stringly-typed keys.
class Env {
  static String get awsRegion => _required('AWS_REGION');
  static String get cognitoIdentityPoolId => _required('COGNITO_IDENTITY_POOL_ID');
  static String get apiGatewayBaseUrl => _required('API_GATEWAY_BASE_URL');

  static String get iotEndpoint => _required('AWS_IOT_ENDPOINT');
  static String get iotThingName => _required('IOT_THING_NAME');
  static String get iotDeviceId => _required('IOT_DEVICE_ID');
  static String get mqttTopicPrefix => _required('MQTT_TOPIC_PREFIX');

  static bool get useMqttRealtime =>
      (dotenv.env['USE_MQTT_REALTIME'] ?? 'false').toLowerCase() == 'true';

  static String get googleMapsApiKey => _required('GOOGLE_MAPS_API_KEY');

  /// True only when `.env` has a real Google Maps key (not `your_key_here`).
  /// Guards the MapScreen so we do not instantiate `GoogleMap` without a
  /// key — doing so crashes iOS natively.
  static bool get hasGoogleMapsKey {
    final key = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    if (key.isEmpty) return false;
    if (key == 'your_key_here') return false;
    if (key.startsWith('your_')) return false;
    // Real Google Maps API keys are typically 39 chars and start with `AIza`.
    return key.startsWith('AIza') && key.length >= 30;
  }

  static String get defaultDeviceId =>
      dotenv.env['DEFAULT_DEVICE_ID'] ?? iotDeviceId;

  static String _required(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StateError(
        'Missing required env var "$key". Copy .env.example to .env and fill it in.',
      );
    }
    return value;
  }
}
