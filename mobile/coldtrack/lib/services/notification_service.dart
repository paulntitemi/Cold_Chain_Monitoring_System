import 'dart:developer' as developer;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/alert.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _initialised = true;
  }

  Future<void> showAlert(Alert alert) async {
    if (!_initialised) await init();

    const channel = AndroidNotificationDetails(
      'coldtrack_alerts',
      'Cold Chain Alerts',
      channelDescription: 'Temperature excursion and spoilage risk alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    try {
      await _plugin.show(
        alert.id.hashCode & 0x7fffffff,
        '${alert.riskLevel.name.toUpperCase()} — ${alert.temperatureAtTrigger.toStringAsFixed(1)}°C',
        'Spoilage risk ${(alert.riskScore * 100).toStringAsFixed(0)}%. '
            '${alert.remainingSafeMinutes}m safe time remaining.',
        const NotificationDetails(android: channel, iOS: ios),
      );
    } catch (e) {
      developer.log('Notification failed: $e', name: 'NotificationService');
    }
  }
}
