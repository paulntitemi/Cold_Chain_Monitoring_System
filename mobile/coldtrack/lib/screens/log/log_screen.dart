import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/alert.dart';
import '../../providers/alert_provider.dart';
import '../../providers/sensor_provider.dart';
import '../../providers/shipment_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/extensions.dart';
import '../../widgets/timeline_entry.dart';

class LogScreen extends ConsumerWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shipment = ref.watch(shipmentProvider);
    final alerts = ref.watch(alertControllerProvider);
    final history = ref.watch(readingHistoryProvider);
    final theme = Theme.of(context);

    final entries = <_LogEntry>[
      if (shipment != null)
        _LogEntry(
          timestamp: shipment.startTime,
          title: 'Trip started',
          detail:
              '${shipment.vaccineType} → ${shipment.destination} (device ${shipment.deviceId})',
          icon: Icons.play_arrow,
        ),
      ...alerts.map((a) => _LogEntry(
            timestamp: a.timestamp,
            title: '${a.riskLevel.label} alert',
            detail:
                '${a.temperatureAtTrigger.toStringAsFixed(1)}°C · risk '
                '${(a.riskScore * 100).toStringAsFixed(0)}% · '
                '${a.response == null ? "no response" : "rider ${a.response!.name}"}',
            icon: _iconFor(a),
          )),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Scaffold(
      appBar: AppBar(title: const Text('Trip Log')),
      floatingActionButton: FloatingActionButton(
        onPressed: entries.isEmpty
            ? null
            : () => _onExport(context, entries.length),
        elevation: 0,
        child: const Icon(Icons.send),
      ),
      body: entries.isEmpty
          ? Center(
              child: Text(
                'No log entries yet.',
                style: theme.textTheme.bodyMedium,
              ),
            )
          : Column(
              children: [
                _SummaryRow(
                  total: entries.length,
                  alerts: alerts.length,
                  samples: history.length,
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: entries.length,
                    itemBuilder: (_, i) => TimelineEntry(
                      // Monochrome for the log screen.
                      dotColor: AppColors.textSecondary,
                      iconOnDot: entries[i].icon,
                      isLast: i == entries.length - 1,
                      child: _LogRow(entry: entries[i]),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _onExport(BuildContext context, int count) {
    // Export hook — in Phase 2 this exports to CSV. For now, acknowledge.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exported $count entries (stub — Phase 2 ships CSV)'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  IconData _iconFor(Alert a) {
    if (a.response == AlertResponse.accepted) return Icons.arrow_forward;
    switch (a.riskLevel) {
      case RiskLevel.critical:
      case RiskLevel.high:
        return Icons.notifications_active;
      case RiskLevel.medium:
        return Icons.thermostat;
      case RiskLevel.low:
      case RiskLevel.unknown:
        return Icons.circle_outlined;
    }
  }
}

class _LogEntry {
  final DateTime timestamp;
  final String title;
  final String detail;
  final IconData icon;

  _LogEntry({
    required this.timestamp,
    required this.title,
    required this.detail,
    required this.icon,
  });
}

class _LogRow extends StatelessWidget {
  final _LogEntry entry;
  const _LogRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(entry.detail, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            entry.timestamp.toLocal().hhmmss,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final int total;
  final int alerts;
  final int samples;

  const _SummaryRow({
    required this.total,
    required this.alerts,
    required this.samples,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _SummaryTile(label: 'EVENTS', value: '$total'),
          const SizedBox(width: 8),
          _SummaryTile(label: 'ALERTS', value: '$alerts'),
          const SizedBox(width: 8),
          _SummaryTile(label: 'SAMPLES', value: '$samples'),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.displaySmall?.copyWith(fontSize: 22),
            ),
          ],
        ),
      ),
    );
  }
}
