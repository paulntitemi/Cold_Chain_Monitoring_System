import 'package:equatable/equatable.dart';

enum IncidentEventType {
  excursionStart,
  alertTriggered,
  actionTaken,
  excursionEnd,
  tripStart,
  tripEnd,
}

extension IncidentEventTypeX on IncidentEventType {
  String get wireName {
    switch (this) {
      case IncidentEventType.excursionStart:
        return 'ExcursionStart';
      case IncidentEventType.alertTriggered:
        return 'AlertTriggered';
      case IncidentEventType.actionTaken:
        return 'ActionTaken';
      case IncidentEventType.excursionEnd:
        return 'ExcursionEnd';
      case IncidentEventType.tripStart:
        return 'TripStart';
      case IncidentEventType.tripEnd:
        return 'TripEnd';
    }
  }
}

class IncidentLog extends Equatable {
  final String deviceId;
  final String shipmentId;
  final DateTime timestamp;
  final IncidentEventType eventType;
  final String detail;
  final Map<String, dynamic>? metadata;

  const IncidentLog({
    required this.deviceId,
    required this.shipmentId,
    required this.timestamp,
    required this.eventType,
    required this.detail,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'shipmentId': shipmentId,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'eventType': eventType.wireName,
        'detail': detail,
        if (metadata != null) 'metadata': metadata,
      };

  factory IncidentLog.fromJson(Map<String, dynamic> json) => IncidentLog(
        deviceId: json['deviceId'] as String,
        shipmentId: json['shipmentId'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        eventType: _parseEventType(json['eventType'] as String),
        detail: json['detail'] as String,
        metadata: json['metadata'] as Map<String, dynamic>?,
      );

  static IncidentEventType _parseEventType(String wire) {
    for (final t in IncidentEventType.values) {
      if (t.wireName == wire) return t;
    }
    return IncidentEventType.actionTaken;
  }

  @override
  List<Object?> get props =>
      [deviceId, shipmentId, timestamp, eventType, detail, metadata];
}
