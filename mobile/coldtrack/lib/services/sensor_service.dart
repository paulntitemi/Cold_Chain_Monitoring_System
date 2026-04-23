import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import '../models/sensor_reading.dart';
import '../utils/constants.dart';
import 'api_service.dart';

/// Aggregate state emitted alongside every reading.
class SensorEvent {
  final SensorReading? reading;
  final SensorStatus status;
  final String? error;

  const SensorEvent({this.reading, required this.status, this.error});
}

/// Polls [ApiService] every 5s for a device's latest readings, emits each new
/// one on a broadcast stream, and tracks a ring buffer of the last N readings
/// for charting.
///
/// Phase 2 note: when `USE_MQTT_REALTIME=true`, the polling loop is replaced
/// by the live MQTT stream from [MqttService]; this class continues to feed
/// the same stream so consumers are transport-agnostic.
class SensorService {
  final ApiService api;
  final String deviceId;

  final Queue<SensorReading> _history = Queue();
  final StreamController<SensorEvent> _events =
      StreamController<SensorEvent>.broadcast();

  Timer? _pollTimer;
  SensorReading? _lastReading;
  DateTime? _lastFetchOkUtc;
  SensorStatus _status = SensorStatus.idle;
  bool _inflight = false;

  SensorService({required this.api, required this.deviceId});

  Stream<SensorEvent> get events => _events.stream;
  SensorReading? get lastReading => _lastReading;
  List<SensorReading> get history => List.unmodifiable(_history);
  SensorStatus get status => _status;

  /// Last successful fetch from the API (for the connectivity banner).
  DateTime? get lastApiSuccessUtc => _lastFetchOkUtc;

  /// Start the polling loop. Idempotent.
  void startMonitoring() {
    if (_pollTimer != null) return;
    developer.log('startMonitoring($deviceId)', name: 'SensorService');

    // Kick off an immediate fetch, then run on a fixed cadence.
    _tick();
    _pollTimer = Timer.periodic(AppConstants.pollInterval, (_) => _tick());
  }

  /// Called when the app resumes from background — fetches immediately.
  void forceRefresh() {
    developer.log('forceRefresh', name: 'SensorService');
    _tick();
  }

  /// Stop polling and release resources.
  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _events.close();
  }

  Future<void> _tick() async {
    if (_inflight) return;
    _inflight = true;
    try {
      final reading = await api.getLatestReading(deviceId);
      if (reading == null) {
        _markMaybeStale();
      } else {
        _ingest(reading);
      }
    } on DioException catch (e) {
      // Cognito-not-configured is an expected, one-time setup state — log
      // it once per startup instead of spamming every 5 seconds.
      if (e.error is CognitoNotConfigured) {
        if (_status != SensorStatus.idle) {
          developer.log(
            'Poll skipped — AWS credentials not configured. '
            'Set COGNITO_IDENTITY_POOL_ID in .env.',
            name: 'SensorService',
          );
        }
        _status = SensorStatus.idle;
        _events.add(SensorEvent(
          reading: _lastReading,
          status: _status,
          error: 'AWS not configured',
        ));
      } else {
        developer.log('Poll failed: ${e.message}', name: 'SensorService');
        _events.add(SensorEvent(
          reading: _lastReading,
          status: _status,
          error: e.message,
        ));
        _markMaybeStale();
      }
    } catch (e, st) {
      developer.log('Poll failed: $e',
          name: 'SensorService', error: e, stackTrace: st);
      _events.add(SensorEvent(
        reading: _lastReading,
        status: _status,
        error: e.toString(),
      ));
      _markMaybeStale();
    } finally {
      _inflight = false;
    }
  }

  /// External hook used by the (Phase 2) MQTT path.
  void ingestExternal(SensorReading reading) => _ingest(reading);

  void _ingest(SensorReading reading) {
    _lastReading = reading;
    _lastFetchOkUtc = DateTime.now().toUtc();

    // Deduplicate by exact timestamp
    if (_history.isEmpty ||
        _history.last.timestamp != reading.timestamp) {
      _history.addLast(reading);
      while (_history.length > AppConstants.readingsRingBufferSize) {
        _history.removeFirst();
      }
    }

    _status = SensorStatus.connected;
    _events.add(SensorEvent(reading: reading, status: _status));
  }

  void _markMaybeStale() {
    final last = _lastFetchOkUtc;
    if (last == null) {
      _status = SensorStatus.idle;
    } else {
      final age = DateTime.now().toUtc().difference(last);
      if (age > AppConstants.staleReadingThreshold) {
        if (_status != SensorStatus.disconnected) {
          _status = SensorStatus.disconnected;
          _events.add(SensorEvent(reading: _lastReading, status: _status));
          developer.log(
            'Sensor marked disconnected — no fresh reading in ${age.inSeconds}s',
            name: 'SensorService',
          );
        }
      }
    }
  }
}
