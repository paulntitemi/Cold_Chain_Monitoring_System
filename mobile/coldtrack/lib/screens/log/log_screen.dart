import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/alert.dart';
import '../../providers/alert_provider.dart';
import '../../providers/sensor_provider.dart';
import '../../providers/shipment_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/extensions.dart';

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
          colour: AppColors.primary,
          icon: Icons.play_arrow,
        ),
      ...alerts.map((a) => _LogEntry(
            timestamp: a.timestamp,
            title: '${a.riskLevel.label} alert — '
                '${a.temperatureAtTrigger.toStringAsFixed(1)} °C',
            detail: a.response == null
                ? 'No response yet'
                : 'Rider ${a.response!.name}',
            colour: a.riskLevel.color,
            icon: _iconFor(a),
          )),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Scaffold(
      appBar: AppBar(title: const Text('Trip Log')),
      body: entries.isEmpty
          ? Center(
              child: Text(
                'No log entries yet.',
                style: theme.textTheme.bodyMedium,
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SummaryRow(
                  total: entries.length,
                  alerts: alerts.length,
                  samples: history.length,
                ),
                const SizedBox(height: 16),
                ...entries.map((e) => _Entry(entry: e)),
              ],
            ),
    );
  }

  IconData _iconFor(Alert a) {
    switch (a.riskLevel) {
      case RiskLevel.critical:
        return Icons.crisis_alert;
      case RiskLevel.high:
        return Icons.warning;
      case RiskLevel.medium:
        return Icons.info_outline;
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
  final Color colour;
  final IconData icon;

  _LogEntry({
    required this.timestamp,
    required this.title,
    required this.detail,
    required this.colour,
    required this.icon,
  });
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
    return Row(
      children: [
        _SummaryTile(label: 'EVENTS', value: '$total'),
        const SizedBox(width: 8),
        _SummaryTile(label: 'ALERTS', value: '$alerts'),
        const SizedBox(width: 8),
        _SummaryTile(label: 'SAMPLES', value: '$samples'),
      ],
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(value, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  final _LogEntry entry;
  const _Entry({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: entry.colour.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: entry.colour.withValues(alpha: 0.2),
            ),
            child: Icon(entry.icon, size: 18, color: entry.colour),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: theme.textTheme.titleMedium),
                Text(entry.detail, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Text(
            entry.timestamp.toLocal().hhmmss,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
