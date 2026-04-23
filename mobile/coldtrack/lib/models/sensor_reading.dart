import 'package:equatable/equatable.dart';

/// A single telemetry reading from an ESP32 sensor, flattened from the
/// DynamoDB / API Gateway response shape.
///
/// The backend exposes readings via:
///   GET /devices/{deviceId}/readings?limit=20
///   GET /devices/{deviceId}/readings/latest
///
/// Expected JSON (tolerant to both flat and nested shapes):
/// ```
/// { "deviceId": "...", "timestamp": "2026-01-01T00:00:00Z",
///   "temperature": 4.2, "humidity": 60.1 }
/// ```
class SensorReading extends Equatable {
  final String deviceId;
  final DateTime timestamp;
  final double temperature;
  final double? humidity;

  const SensorReading({
    required this.deviceId,
    required this.timestamp,
    required this.temperature,
    this.humidity,
  });

  factory SensorReading.fromJson(Map<String, dynamic> json) {
    // The backend has historically used either top-level fields or a
    // nested "sensors" object (matches the ESP32 firmware payload).
    final sensors = json['sensors'] as Map<String, dynamic>?;

    final deviceId = (json['deviceId'] ?? json['device_id'] ?? '') as String;

    final rawTimestamp = json['timestamp'] ?? json['time'] ?? json['epoch_ms'];
    final timestamp = _parseTimestamp(rawTimestamp);

    final rawTemp = sensors?['temperature'] ?? json['temperature'];
    final rawHumidity = sensors?['humidity'] ?? json['humidity'];

    return SensorReading(
      deviceId: deviceId,
      timestamp: timestamp,
      temperature: (rawTemp as num?)?.toDouble() ?? 0.0,
      humidity: (rawHumidity as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'temperature': temperature,
        if (humidity != null) 'humidity': humidity,
      };

  static DateTime _parseTimestamp(dynamic raw) {
    if (raw == null) return DateTime.now().toUtc();
    if (raw is int) {
      // epoch_ms (>10 digits) vs epoch_s
      return raw > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(raw * 1000, isUtc: true);
    }
    if (raw is String) {
      return DateTime.tryParse(raw)?.toUtc() ?? DateTime.now().toUtc();
    }
    return DateTime.now().toUtc();
  }

  @override
  List<Object?> get props => [deviceId, timestamp, temperature, humidity];
}

/// Connection / freshness state of the sensor stream.
enum SensorStatus { connected, disconnected, idle }
