import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sensor_reading.dart';
import '../providers/sensor_provider.dart';
import '../providers/storage_centre_provider.dart';
import '../services/location_service.dart';
import '../services/sensor_service.dart';
import '../theme/app_theme.dart';
import '../utils/extensions.dart';

enum _PillHealth { healthy, degraded, down }

/// Persistent status row showing API / GPS / Sensor health.
/// Healthy pills collapse to a 6px dot; degraded/down pills expand with
/// a label so problems get the rider's attention.
class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(sensorEventProvider);
    final location = ref.watch(locationServiceProvider);
    final riderPos = ref.watch(riderPositionProvider);

    final (apiHealth, apiSince) = _apiHealth(event);
    final (sensorHealth, sensorSince) = _sensorHealth(event);
    final (gpsHealth, gpsSince) = _gpsHealth(location, riderPos);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _StatusPill(label: 'API', health: apiHealth, lastSuccess: apiSince),
          const SizedBox(width: 10),
          _StatusPill(label: 'GPS', health: gpsHealth, lastSuccess: gpsSince),
          const SizedBox(width: 10),
          _StatusPill(
              label: 'SENSOR',
              health: sensorHealth,
              lastSuccess: sensorSince),
          const Spacer(),
          if (apiSince != null)
            Text(
              'synced ${apiSince.toLocal().relativeToNow}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
            ),
        ],
      ),
    );
  }

  (_PillHealth, DateTime?) _apiHealth(AsyncValue<SensorEvent> event) {
    return event.when(
      data: (e) => (_PillHealth.healthy, DateTime.now()),
      error: (_, __) => (_PillHealth.down, null),
      loading: () => (_PillHealth.degraded, null),
    );
  }

  (_PillHealth, DateTime?) _sensorHealth(AsyncValue<SensorEvent> event) {
    final e = event.valueOrNull;
    if (e == null) return (_PillHealth.degraded, null);
    switch (e.status) {
      case SensorStatus.connected:
        return (_PillHealth.healthy, e.reading?.timestamp);
      case SensorStatus.disconnected:
        return (_PillHealth.down, e.reading?.timestamp);
      case SensorStatus.idle:
        return (_PillHealth.degraded, e.reading?.timestamp);
    }
  }

  (_PillHealth, DateTime?) _gpsHealth(
    LocationService location,
    AsyncValue<dynamic> position,
  ) {
    switch (location.status) {
      case LocationStatus.available:
        return (_PillHealth.healthy, location.last?.capturedAtUtc);
      case LocationStatus.permissionDenied:
      case LocationStatus.disabled:
        return (_PillHealth.down, null);
      case LocationStatus.unknown:
        return (_PillHealth.degraded, null);
    }
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final _PillHealth health;
  final DateTime? lastSuccess;

  const _StatusPill({
    required this.label,
    required this.health,
    required this.lastSuccess,
  });

  Color get _colour {
    switch (health) {
      case _PillHealth.healthy:
        return AppColors.safe;
      case _PillHealth.degraded:
        return AppColors.warning;
      case _PillHealth.down:
        return AppColors.danger;
    }
  }

  String get _tooltip {
    final healthLabel = health.name.toUpperCase();
    if (lastSuccess == null) return '$label $healthLabel — no data yet';
    return '$label $healthLabel — last ${lastSuccess!.toLocal().relativeToNow}';
  }

  @override
  Widget build(BuildContext context) {
    // Healthy → collapsed 6px dot only. Degraded / down → expanded with label.
    final collapsed = health == _PillHealth.healthy;

    return Tooltip(
      message: _tooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: collapsed
            ? const EdgeInsets.all(3)
            : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _colour.withValues(alpha: collapsed ? 0.0 : 0.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _colour.withValues(alpha: collapsed ? 0.0 : 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _colour,
                boxShadow: [
                  BoxShadow(
                    color: _colour.withValues(alpha: 0.7),
                    blurRadius: collapsed ? 4 : 6,
                  ),
                ],
              ),
            ),
            if (!collapsed) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: _colour,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
