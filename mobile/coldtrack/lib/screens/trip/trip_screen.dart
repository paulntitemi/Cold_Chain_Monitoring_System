import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/sensor_reading.dart';
import '../../models/storage_centre.dart';
import '../../providers/sensor_provider.dart';
import '../../providers/shipment_provider.dart';
import '../../providers/storage_centre_provider.dart';
import '../../services/risk_engine.dart';
import '../../theme/app_theme.dart';
import '../../widgets/connectivity_banner.dart';
import '../../widgets/dot_grid_background.dart';
import '../../widgets/risk_gauge.dart';
import '../../widgets/stat_pill.dart';
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
        title: Text(
          shipment?.destination.toUpperCase() ?? 'LIVE TRIP',
          style: const TextStyle(letterSpacing: 1.2),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'End trip',
            onPressed: () => _confirmEnd(context, ref),
          ),
        ],
      ),
      body: DotGridBackground(
        child: Column(
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
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    if (shipment != null) _TripHeader(
                      vaccine: shipment.vaccineType,
                      deviceId: shipment.deviceId,
                      rider: shipment.riderName,
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: RiskGauge(
                        score: risk.riskScore,
                        level: risk.level,
                        size: 280,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _StatPillRow(reading: reading, risk: risk),
                    const SizedBox(height: 16),
                    _ChartCard(reading: reading, history: history, risk: risk),
                    const SizedBox(height: 16),
                    _MorphingActionCard(risk: risk),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmEnd(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('End trip?'),
        content: const Text(
          'Monitoring stops and the trip is logged.',
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

// ---------------------------------------------------------------------------
// Header — vaccine type + rider + device id, inline
// ---------------------------------------------------------------------------
class _TripHeader extends StatelessWidget {
  final String vaccine;
  final String deviceId;
  final String rider;

  const _TripHeader({
    required this.vaccine,
    required this.deviceId,
    required this.rider,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_shipping,
                size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vaccine, style: theme.textTheme.titleMedium),
                Text('$rider · $deviceId',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Three stat pills: TEMP | SAFE TIME | EXCURSION
// ---------------------------------------------------------------------------
class _StatPillRow extends ConsumerWidget {
  final SensorReading? reading;
  final RiskAssessment risk;

  const _StatPillRow({required this.reading, required this.risk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tempString =
        reading == null ? '—' : '${reading!.temperature.toStringAsFixed(1)}°';
    final safeString = risk.remainingSafeMinutes.toString();
    final excursionSeconds =
        ref.watch(excursionTrackerProvider.notifier).liveSeconds;
    final excursionString = _mmss(excursionSeconds);
    final tempColour = reading == null ? AppColors.textSecondary : risk.level.color;

    return Row(
      children: [
        Expanded(
          child: StatPill(
            label: 'TEMP',
            value: tempString,
            valueColour: tempColour,
            icon: Icons.thermostat,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatPill(
            label: 'SAFE LEFT',
            value: '${safeString}m',
            valueColour: risk.level.color,
            icon: Icons.shield_outlined,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatPill(
            label: 'EXCURSION',
            value: excursionString,
            icon: Icons.timer_outlined,
          ),
        ),
      ],
    );
  }

  String _mmss(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ---------------------------------------------------------------------------
// Compact chart
// ---------------------------------------------------------------------------
class _ChartCard extends StatelessWidget {
  final SensorReading? reading;
  final List<SensorReading> history;
  final RiskAssessment risk;

  const _ChartCard({
    required this.reading,
    required this.history,
    required this.risk,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('LAST 50 READINGS',
                  style: theme.textTheme.labelLarge),
              const Spacer(),
              if (reading?.humidity != null)
                Text(
                  'HUM ${reading!.humidity!.toStringAsFixed(0)}%',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: TemperatureChart(readings: history),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom action card that morphs on HIGH / CRITICAL:
//   LOW/MED  → small row: status icon + single-line action
//   HIGH/CRI → expands to a mini bottom-sheet with recommended centre + CTA
// ---------------------------------------------------------------------------
class _MorphingActionCard extends ConsumerWidget {
  final RiskAssessment risk;

  const _MorphingActionCard({required this.risk});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final expanded = risk.level == RiskLevel.high ||
        risk.level == RiskLevel.critical;
    final colour = risk.level.color;

    final (IconData icon, String action) = _copy(risk.level);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.all(expanded ? 20 : 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colour.withValues(alpha: 0.5)),
        boxShadow: expanded
            ? [
                BoxShadow(
                  color: colour.withValues(alpha: 0.25),
                  blurRadius: 24,
                ),
              ]
            : null,
      ),
      child: expanded
          ? _expandedBody(context, ref, theme, colour, icon, action)
          : _collapsedBody(theme, colour, icon, action),
    );
  }

  Widget _collapsedBody(
      ThemeData theme, Color colour, IconData icon, String action) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: colour),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NEXT ACTION',
                  style: theme.textTheme.labelLarge),
              const SizedBox(height: 2),
              Text(action, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      ],
    );
  }

  Widget _expandedBody(BuildContext context, WidgetRef ref, ThemeData theme,
      Color colour, IconData icon, String action) {
    final nearbyAsync = ref.watch(nearbyCentresProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colour.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colour),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(risk.level.label,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: colour, letterSpacing: 1.8)),
                  const SizedBox(height: 2),
                  Text(action, style: theme.textTheme.headlineSmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        nearbyAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Routing unavailable',
              style: theme.textTheme.bodySmall),
          data: (centres) {
            if (centres.isEmpty) {
              return Text(
                'No nearby centres within radius — contact control centre.',
                style: theme.textTheme.bodySmall,
              );
            }
            final top = centres.first;
            return _RecommendedCentreRow(centre: top);
          },
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: () => _onDivert(context),
          icon: const Icon(Icons.alt_route, size: 18),
          label: const Text('DIVERT NOW'),
          style: ElevatedButton.styleFrom(
            backgroundColor: colour,
            foregroundColor: AppColors.background,
          ),
        ),
      ],
    );
  }

  void _onDivert(BuildContext context) {
    // Navigate to map so the rider can see the route.
    // GoRouter is aware of /map — we use the hosting shell's navigation.
    Navigator.of(context).maybePop();
    // Router redirect happens on the active shell — the bottom nav handles it.
  }

  (IconData, String) _copy(RiskLevel level) {
    switch (level) {
      case RiskLevel.low:
        return (Icons.check_circle, 'Continue to destination');
      case RiskLevel.medium:
        return (Icons.warning_amber, 'Monitor closely — check the unit');
      case RiskLevel.high:
        return (Icons.alt_route, 'Divert to nearest cold storage');
      case RiskLevel.critical:
        return (Icons.emergency, 'IMMEDIATE DIVERT — spoilage imminent');
      case RiskLevel.unknown:
        return (Icons.hourglass_empty, 'Waiting for sensor data…');
    }
  }
}

class _RecommendedCentreRow extends StatelessWidget {
  final StorageCentre centre;
  const _RecommendedCentreRow({required this.centre});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_pharmacy,
                size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(centre.name, style: theme.textTheme.titleMedium),
                Text(
                  '${centre.distanceKm?.toStringAsFixed(1) ?? '—'} km · '
                  '${centre.estimatedMinutes ?? '—'} min',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
