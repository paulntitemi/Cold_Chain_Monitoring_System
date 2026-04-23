import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/sensor_reading.dart';
import '../../providers/sensor_provider.dart';
import '../../providers/shipment_provider.dart';
import '../../providers/storage_centre_provider.dart';
import '../../services/risk_engine.dart';
import '../../theme/app_theme.dart';
import '../../widgets/connectivity_banner.dart';
import '../../widgets/countdown_timer.dart';
import '../../widgets/risk_gauge.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/temperature_chart.dart';

class TripScreen extends ConsumerWidget {
  const TripScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shipment = ref.watch(shipmentProvider);
    final reading = ref.watch(latestReadingProvider);
    final risk = ref.watch(riskAssessmentProvider);
    final history = ref.watch(readingHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Trip'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'End trip',
            onPressed: () => _confirmEnd(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          const ConnectivityBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                final deviceId = ref.read(activeDeviceIdProvider);
                ref.read(sensorServiceProvider(deviceId)).forceRefresh();
                await Future.delayed(const Duration(milliseconds: 500));
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (shipment != null) _ShipmentSummary(shipment: shipment.destination, vaccine: shipment.vaccineType),
                  const SizedBox(height: 16),
                  _RiskCard(risk: risk, reading: reading),
                  const SizedBox(height: 16),
                  _TempCard(reading: reading, risk: risk, history: history),
                  const SizedBox(height: 16),
                  _NextActionCard(risk: risk),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmEnd(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('End trip?'),
        content: const Text(
          'The monitoring session will stop and the trip will be logged.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('End Trip')),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(shipmentProvider.notifier).endTrip();
    }
  }
}

class _ShipmentSummary extends StatelessWidget {
  final String shipment;
  final String vaccine;
  const _ShipmentSummary({required this.shipment, required this.vaccine});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.local_shipping, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shipment,
                      style: theme.textTheme.titleMedium, maxLines: 1),
                  Text(vaccine, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskCard extends StatelessWidget {
  final RiskAssessment risk;
  final SensorReading? reading;

  const _RiskCard({required this.risk, required this.reading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Text('SPOILAGE RISK',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: AppColors.textSecondary)),
                const Spacer(),
                StatusBadge(level: risk.level),
              ],
            ),
            const SizedBox(height: 20),
            RiskGauge(score: risk.riskScore, level: risk.level),
            const SizedBox(height: 20),
            CountdownTimer(
              initialSeconds: risk.remainingSafeMinutes * 60,
              level: risk.level,
            ),
          ],
        ),
      ),
    );
  }
}

class _TempCard extends StatelessWidget {
  final SensorReading? reading;
  final RiskAssessment risk;
  final List<SensorReading> history;

  const _TempCard({
    required this.reading,
    required this.risk,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tempColour = risk.level.color;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('TEMPERATURE',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: AppColors.textSecondary)),
                const Spacer(),
                Text(
                  reading == null
                      ? '—'
                      : '${reading!.temperature.toStringAsFixed(2)} °C',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    color: tempColour,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (reading?.humidity != null)
              Text(
                'Humidity ${reading!.humidity!.toStringAsFixed(1)}%',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: TemperatureChart(readings: history),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextActionCard extends ConsumerWidget {
  final RiskAssessment risk;
  const _NextActionCard({required this.risk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nearbyAsync = ref.watch(nearbyCentresProvider);
    final theme = Theme.of(context);

    String action;
    IconData icon;
    switch (risk.level) {
      case RiskLevel.low:
        action = 'Continue to destination';
        icon = Icons.check_circle;
        break;
      case RiskLevel.medium:
        action = 'Monitor closely — consider pulling over to check the unit';
        icon = Icons.warning_amber;
        break;
      case RiskLevel.high:
        action = 'Divert to nearest cold storage centre';
        icon = Icons.alt_route;
        break;
      case RiskLevel.critical:
        action = 'IMMEDIATE DIVERT — risk of spoilage imminent';
        icon = Icons.emergency;
        break;
      case RiskLevel.unknown:
        action = 'Waiting for sensor data…';
        icon = Icons.hourglass_empty;
    }

    final colour = risk.level.color;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colour),
                const SizedBox(width: 8),
                Text('NEXT ACTION',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 12),
            Text(action, style: theme.textTheme.titleMedium),
            if (risk.level == RiskLevel.high ||
                risk.level == RiskLevel.critical) ...[
              const SizedBox(height: 16),
              nearbyAsync.when(
                data: (centres) {
                  if (centres.isEmpty) {
                    return Text(
                      'No nearby centres found — contact control centre',
                      style: theme.textTheme.bodySmall,
                    );
                  }
                  final top = centres.first;
                  return Row(
                    children: [
                      const Icon(Icons.local_pharmacy,
                          color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(top.name, style: theme.textTheme.titleMedium),
                            Text(
                              '${top.distanceKm?.toStringAsFixed(1)} km · '
                              '${top.estimatedMinutes} min',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Routing unavailable: $e',
                    style: theme.textTheme.bodySmall),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
