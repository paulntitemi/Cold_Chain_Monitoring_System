import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/alert.dart';
import '../models/incident_log.dart';
import '../models/storage_centre.dart';
import '../services/notification_service.dart';
import '../services/risk_engine.dart';
import '../theme/app_theme.dart';
import '../utils/constants.dart';
import 'sensor_provider.dart';
import 'shipment_provider.dart';
import 'storage_centre_provider.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  service.init();
  return service;
});

class AlertController extends StateNotifier<List<Alert>> {
  final Ref ref;
  RiskLevel _lastEmittedLevel = RiskLevel.low;
  DateTime? _lastCriticalEmittedAt;

  AlertController(this.ref) : super(const []);

  /// Called whenever the risk assessment changes. Raises a new [Alert] when
  /// the level ticks up into warning/critical territory; re-emits a critical
  /// alert every [AppConstants.criticalAlertRetriggerAfter] if the rider has
  /// not responded.
  void onRiskChange(RiskAssessment a) {
    final level = a.level;
    final nowUtc = DateTime.now().toUtc();
    final shouldEmit = _shouldEmit(level, nowUtc);

    if (!shouldEmit) return;

    final recommended = _pickRecommendedCentre();
    final alert = Alert(
      id: const Uuid().v4(),
      timestamp: nowUtc,
      riskLevel: level,
      temperatureAtTrigger: a.temperature,
      riskScore: a.riskScore,
      remainingSafeMinutes: a.remainingSafeMinutes,
      recommendedCentre: recommended,
    );

    state = [alert, ...state];
    _lastEmittedLevel = level;
    if (level == RiskLevel.critical) _lastCriticalEmittedAt = nowUtc;

    _notify(alert);
    _logIncident(alert);
  }

  /// Rider response — accepted, ignored, or escalated.
  void respondTo(String alertId, AlertResponse response) {
    state = [
      for (final a in state)
        if (a.id == alertId) a.copyWith(response: response) else a,
    ];
    if (response == AlertResponse.ignored) {
      developer.log('Rider ignored alert $alertId', name: 'AlertController');
    }
  }

  // -------------------------------------------------------------------------
  // Internal
  // -------------------------------------------------------------------------

  bool _shouldEmit(RiskLevel level, DateTime now) {
    if (level == RiskLevel.low || level == RiskLevel.unknown) {
      _lastEmittedLevel = level;
      return false;
    }
    if (level.index > _lastEmittedLevel.index) return true;

    // Re-trigger critical every N minutes if the rider hasn't responded.
    if (level == RiskLevel.critical && _lastCriticalEmittedAt != null) {
      final unresponded = state.isNotEmpty &&
          state.first.riskLevel == RiskLevel.critical &&
          state.first.response == null;
      final since = now.difference(_lastCriticalEmittedAt!);
      if (unresponded && since >= AppConstants.criticalAlertRetriggerAfter) {
        return true;
      }
    }
    return false;
  }

  StorageCentre? _pickRecommendedCentre() {
    final nearby = ref.read(nearbyCentresProvider);
    return nearby.maybeWhen(data: (list) => list.isNotEmpty ? list.first : null,
        orElse: () => null);
  }

  Future<void> _notify(Alert alert) async {
    final service = ref.read(notificationServiceProvider);
    await service.showAlert(alert);
  }

  Future<void> _logIncident(Alert alert) async {
    final shipment = ref.read(shipmentProvider);
    if (shipment == null) return;

    final api = ref.read(apiServiceProvider);
    final incident = IncidentLog(
      deviceId: shipment.deviceId,
      shipmentId: shipment.id,
      timestamp: alert.timestamp,
      eventType: IncidentEventType.alertTriggered,
      detail: 'Risk ${(alert.riskScore * 100).toStringAsFixed(0)}% — '
          '${alert.temperatureAtTrigger.toStringAsFixed(1)}°C '
          '(${alert.riskLevel.name})',
      metadata: {
        'riskScore': alert.riskScore,
        'remainingSafeMinutes': alert.remainingSafeMinutes,
      },
    );
    try {
      await api.logIncident(incident);
    } catch (e) {
      developer.log('Incident log POST failed (non-fatal): $e',
          name: 'AlertController');
    }
  }
}

final alertControllerProvider =
    StateNotifierProvider<AlertController, List<Alert>>((ref) {
  final controller = AlertController(ref);
  // React to every risk assessment change.
  ref.listen<RiskAssessment>(riskAssessmentProvider, (_, next) {
    controller.onRiskChange(next);
  });
  return controller;
});
