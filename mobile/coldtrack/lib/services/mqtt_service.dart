import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../config/env.dart';
import '../models/sensor_reading.dart';
import 'cognito_service.dart';
import 'sensor_service.dart';

/// PHASE 2 — MQTT over WebSockets to AWS IoT Core.
///
/// Gated by [Env.useMqttRealtime]. When false (Phase 1 default) this class
/// no-ops with a log line so the rest of the app can keep the same wiring.
/// When true (Phase 2), it opens a SigV4-signed WebSocket to IoT Core,
/// subscribes to the device's telemetry topic, and feeds every inbound
/// payload into [SensorService.ingestExternal] — the polling loop can then
/// be stopped.
///
/// The signed WebSocket URL must be generated from the Cognito temporary
/// credentials using SigV4 presigned URL rules for IoT Core. The signing
/// logic is scaffolded below but intentionally left stubbed — finalise
/// when Phase 2 begins.
class MqttService {
  final CognitoService cognito;
  final SensorService sensorService;
  final String deviceId;
  final String topicPrefix;
  final String endpoint;

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _sub;
  int _reconnectAttempt = 0;

  MqttService({
    required this.cognito,
    required this.sensorService,
    required this.deviceId,
    required this.topicPrefix,
    required this.endpoint,
  });

  factory MqttService.fromEnv({
    required CognitoService cognito,
    required SensorService sensorService,
  }) =>
      MqttService(
        cognito: cognito,
        sensorService: sensorService,
        deviceId: Env.iotDeviceId,
        topicPrefix: Env.mqttTopicPrefix,
        endpoint: Env.iotEndpoint,
      );

  String get _telemetryTopic => '$topicPrefix/$deviceId/telemetry';

  /// Connect and subscribe. No-op when the feature flag is off.
  Future<void> connect() async {
    if (!Env.useMqttRealtime) {
      developer.log(
        'MQTT disabled — using REST polling',
        name: 'MqttService',
      );
      return;
    }

    try {
      final url = await _buildSignedWebSocketUrl();
      final client = MqttServerClient.withPort(url, 'coldtrack-$deviceId', 443);
      client.useWebSocket = true;
      client.logging(on: false);
      client.keepAlivePeriod = 60;
      client.autoReconnect = false;
      client.onConnected = _onConnected;
      client.onDisconnected = _onDisconnected;
      client.onSubscribed = (topic) => developer.log(
            'Subscribed to $topic',
            name: 'MqttService',
          );

      final connMessage = MqttConnectMessage()
          .withClientIdentifier('coldtrack-$deviceId')
          .startClean();
      client.connectionMessage = connMessage;

      await client.connect();
      _client = client;
      _reconnectAttempt = 0;

      client.subscribe(_telemetryTopic, MqttQos.atLeastOnce);
      _sub = client.updates!.listen(_onMessage);
    } catch (e, st) {
      developer.log('MQTT connect failed: $e',
          name: 'MqttService', error: e, stackTrace: st);
      _scheduleReconnect();
    }
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    _client?.disconnect();
    _client = null;
  }

  // -------------------------------------------------------------------------
  // Internal
  // -------------------------------------------------------------------------

  void _onConnected() {
    developer.log('MQTT connected', name: 'MqttService');
  }

  void _onDisconnected() {
    developer.log('MQTT disconnected', name: 'MqttService');
    _scheduleReconnect();
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> batch) {
    for (final msg in batch) {
      final publish = msg.payload as MqttPublishMessage;
      final payloadString = MqttPublishPayload.bytesToStringAsString(
        publish.payload.message,
      );
      try {
        final json = jsonDecode(payloadString) as Map<String, dynamic>;
        final reading = SensorReading.fromJson(json);
        sensorService.ingestExternal(reading);
      } catch (e) {
        developer.log(
          'Failed to parse MQTT payload: $e ($payloadString)',
          name: 'MqttService',
        );
      }
    }
  }

  void _scheduleReconnect() {
    if (!Env.useMqttRealtime) return;
    _reconnectAttempt++;
    final backoffSeconds =
        (1 << _reconnectAttempt).clamp(1, 60); // 2, 4, 8 … up to 60s
    developer.log(
      'Reconnecting in ${backoffSeconds}s (attempt $_reconnectAttempt)',
      name: 'MqttService',
    );
    Future.delayed(Duration(seconds: backoffSeconds), connect);
  }

  /// Builds a SigV4-signed WebSocket URL for `wss://{endpoint}/mqtt`.
  ///
  /// TODO(phase2): implement SigV4 query-string signing using
  /// `aws_signature_v4`'s presigned-URL helpers. The AWS docs describe the
  /// exact canonical-request shape required by IoT Core.
  Future<String> _buildSignedWebSocketUrl() async {
    // Ensure fresh credentials are available before signing.
    await cognito.getCredentials();
    // Placeholder URL — do not use as-is. Replace with the signed variant.
    return 'wss://$endpoint/mqtt';
  }
}
