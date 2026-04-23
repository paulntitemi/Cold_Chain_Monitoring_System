import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sensor_reading.dart';
import '../services/api_service.dart';
import '../services/mqtt_service.dart';
import '../services/risk_engine.dart';
import '../services/sensor_service.dart';
import 'auth_provider.dart';
import 'shipment_provider.dart';

// ---------------------------------------------------------------------------
// Core services
// ---------------------------------------------------------------------------

final apiServiceProvider = Provider<ApiService>((ref) {
  final cognito = ref.watch(cognitoServiceProvider);
  return ApiService.build(cognito: cognito);
});

final riskEngineProvider = Provider<RiskEngine>((ref) => const RiskEngine());

/// One [SensorService] per device. Auto-disposed when the device ID changes.
final sensorServiceProvider =
    Provider.family<SensorService, String>((ref, deviceId) {
  final api = ref.watch(apiServiceProvider);
  final service = SensorService(api: api, deviceId: deviceId);
  service.startMonitoring();
  ref.onDispose(service.stop);
  return service;
});

/// Phase-2 MQTT client. Fires `connect()` which no-ops when the flag is off.
final mqttServiceProvider =
    Provider.family<MqttService, String>((ref, deviceId) {
  final cognito = ref.watch(cognitoServiceProvider);
  final sensor = ref.watch(sensorServiceProvider(deviceId));
  final mqtt = MqttService(
    cognito: cognito,
    sensorService: sensor,
    deviceId: deviceId,
    topicPrefix: 'coldtrack',
    endpoint: '',
  );
  mqtt.connect();
  ref.onDispose(mqtt.disconnect);
  return mqtt;
});

// ---------------------------------------------------------------------------
// Streams keyed off the active shipment's device ID
// ---------------------------------------------------------------------------

final _activeSensorServiceProvider = Provider<SensorService>((ref) {
  final deviceId = ref.watch(activeDeviceIdProvider);
  return ref.watch(sensorServiceProvider(deviceId));
});

/// Emits every [SensorEvent] (reading + status) from the active device.
final sensorEventProvider = StreamProvider<SensorEvent>((ref) {
  final service = ref.watch(_activeSensorServiceProvider);
  final controller = StreamController<SensorEvent>.broadcast();
  if (service.lastReading != null) {
    controller.add(SensorEvent(
      reading: service.lastReading,
      status: service.status,
    ));
  }
  final sub = service.events.listen(controller.add);
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});

/// The latest known reading (non-null once any data has arrived).
final latestReadingProvider = Provider<SensorReading?>((ref) {
  final event = ref.watch(sensorEventProvider);
  return event.maybeWhen(
    data: (e) => e.reading,
    orElse: () => ref.watch(_activeSensorServiceProvider).lastReading,
  );
});

/// Historical ring buffer, used by the chart.
final readingHistoryProvider = Provider<List<SensorReading>>((ref) {
  // Rebuild whenever a new event lands so the chart stays live.
  ref.watch(sensorEventProvider);
  return ref.watch(_activeSensorServiceProvider).history;
});

/// Running tally of seconds spent outside the safe range for the current trip.
/// Resets when shipment changes.
class ExcursionTracker extends StateNotifier<int> {
  ExcursionTracker() : super(0);
  DateTime? _currentExcursionStart;

  void update({required bool isOutsideRange, required DateTime nowUtc}) {
    if (isOutsideRange) {
      _currentExcursionStart ??= nowUtc;
    } else if (_currentExcursionStart != null) {
      state += nowUtc.difference(_currentExcursionStart!).inSeconds;
      _currentExcursionStart = null;
    }
  }

  int get liveSeconds {
    if (_currentExcursionStart == null) return state;
    return state +
        DateTime.now().toUtc().difference(_currentExcursionStart!).inSeconds;
  }

  void reset() {
    state = 0;
    _currentExcursionStart = null;
  }
}

final excursionTrackerProvider =
    StateNotifierProvider<ExcursionTracker, int>((ref) => ExcursionTracker());

/// Current [RiskAssessment] derived from the latest reading + excursion time.
final riskAssessmentProvider = Provider<RiskAssessment>((ref) {
  final reading = ref.watch(latestReadingProvider);
  final engine = ref.watch(riskEngineProvider);
  final tracker = ref.read(excursionTrackerProvider.notifier);

  if (reading == null) return RiskAssessment.unknown;

  final assessment = engine.assess(
    reading: reading,
    durationOutsideRangeSeconds: tracker.liveSeconds,
  );

  // Side-effect: feed the tracker with this reading's range-status.
  tracker.update(
    isOutsideRange: assessment.isOutsideRange,
    nowUtc: reading.timestamp.toUtc(),
  );

  return assessment;
});
